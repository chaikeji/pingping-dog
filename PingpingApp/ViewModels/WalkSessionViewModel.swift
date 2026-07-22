import Foundation
import SwiftData
import CoreLocation
import Combine

/// 一次遛狗会话的状态（PRD §5.3）。记录距离/时长，以及尿尿/拉屎/遇到的狗朋友/拍照；
/// 支持暂停（暂停不计时）。结束时静默识别常走路线、给遇到的狗朋友 +1 亲密度、算当天是否达标。
@MainActor
final class WalkSessionViewModel: ObservableObject {
    @Published var elapsedSeconds: Int = 0        // 有效计时（扣掉暂停）
    @Published var distanceMeters: Double = 0
    @Published var isPaused = false
    @Published var peeCount = 0
    @Published var poopCount = 0
    /// 每次点尿尿/拉屎在当时定位落下的图钉。用 RoutePoint 是为了带上时间戳、方便入库。
    @Published var peeSpots: [RoutePoint] = []
    @Published var poopSpots: [RoutePoint] = []
    @Published var metFriendIDs: Set<UUID> = []
    @Published var photos: [Data] = []
    /// 定位授权状态（从 locationManager 转发过来，供界面判断是否需要提示降级）。
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    let locationManager = LocationManager()
    private let matcher = RouteMatchingService()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// 最近一次刷盘时间：timer 每秒都会看一眼，超过 3 秒就写一次快照。
    /// 单独存时间戳，是因为 elapsedSeconds 在暂停期间不推进，靠取模会漏掉暂停期的保存。
    private var lastSnapshotAt: Date = .distantPast

    /// 当天累计达标阈值：15 分钟。
    static let dailyGoalSeconds = 15 * 60

    var isTracking: Bool { locationManager.isTracking }

    /// 定位权限是否不足以在后台/锁屏持续记录（非「始终允许」）。
    var locationInsufficient: Bool {
        switch authorizationStatus {
        case .authorizedAlways: return false
        default: return true
        }
    }

    init() {
        // 把 locationManager 的授权状态转发到本 VM，界面 observe 本 VM 即可收到变化。
        locationManager.$authorizationStatus
            .receive(on: RunLoop.main)
            .assign(to: &$authorizationStatus)
        // 每次定位更新都触发本 VM 的 objectWillChange，让 view 立刻重绘。
        // 不接的话 view 只有每秒 timer 触发才刷新，会出现「路线正确、狗头/自己位置晃后一秒」的错位。
        locationManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startTracking()
        elapsedSeconds = 0
        distanceMeters = 0
        isPaused = false
        peeCount = 0
        poopCount = 0
        peeSpots = []
        poopSpots = []
        metFriendIDs = []
        photos = []
        lastSnapshotAt = .distantPast
        startTimer()
    }

    /// 断点续遛：把上次的轨迹和计次装回来，接着走。
    /// 照片和图钉按 §7 用户敲定的方案不带回（只带轨迹 + 计次 + 遇到的朋友）。
    func resume(from snapshot: InProgressWalkSnapshot) {
        locationManager.requestAlwaysAuthorization()
        locationManager.startTracking(preloadedPoints: snapshot.points)
        elapsedSeconds = snapshot.elapsedSeconds
        distanceMeters = Self.totalDistance(points: snapshot.points)
        isPaused = snapshot.isPaused
        peeCount = snapshot.peeCount
        poopCount = snapshot.poopCount
        peeSpots = []
        poopSpots = []
        metFriendIDs = Set(snapshot.metFriendIDs)
        photos = []
        lastSnapshotAt = .distantPast
        startTimer()
        // 立即回写一次：让 savedAt 追上现在时间，接下来这次会话的过期倒计时按最新起。
        persistSnapshot()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isPaused {
                    self.elapsedSeconds += 1
                    self.distanceMeters = Self.totalDistance(points: self.locationManager.currentPoints)
                }
                // 暂停期间也刷盘：暂停中 App 被 kill 也要能捞回来。
                if Date.now.timeIntervalSince(self.lastSnapshotAt) >= 3 {
                    self.persistSnapshot()
                }
            }
        }
    }

    /// 把当前会话状态刷一次到磁盘。App 进入后台时也会主动调这个。
    /// 还没落下第一个定位点前不写：没起点就没法算过期，索性等有点再持久化。
    func persistSnapshot() {
        let points = locationManager.currentPoints
        guard let startDate = points.first?.timestamp else { return }
        let snapshot = InProgressWalkSnapshot(
            startDate: startDate,
            savedAt: .now,
            points: points,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            peeCount: peeCount,
            poopCount: poopCount,
            metFriendIDs: Array(metFriendIDs),
            isPaused: isPaused
        )
        InProgressWalkStore.save(snapshot)
        lastSnapshotAt = .now
    }

    /// 主动放弃当前会话（距离太短确认结束、或用户在续遛提示上选「放弃」都会走这里）。
    func discard() {
        timer?.invalidate()
        timer = nil
        _ = locationManager.stopTracking()
        InProgressWalkStore.clear()
    }

    func togglePause() { isPaused.toggle() }
    func addPee() {
        peeCount += 1
        if let here = locationManager.currentPoints.last?.coordinate {
            peeSpots.append(RoutePoint(coordinate: here))
        }
    }
    func addPoop() {
        poopCount += 1
        if let here = locationManager.currentPoints.last?.coordinate {
            poopSpots.append(RoutePoint(coordinate: here))
        }
    }
    func addPhoto(_ data: Data) { photos.append(data) }
    func toggleFriend(_ id: UUID) {
        if metFriendIDs.contains(id) { metFriendIDs.remove(id) } else { metFriendIDs.insert(id) }
    }

    /// 当前距离是否达到可保存的最小值（100 米）。
    var meetsMinDistance: Bool { distanceMeters >= 100 }

    /// 结束并保存。距离过短（<100m）或轨迹点不足时不保存、返回 nil；
    /// 保存成功返回 WalkRoute 供本次总结页展示。
    @discardableResult
    func finish(context: ModelContext, ownerID: String? = nil) -> WalkRoute? {
        timer?.invalidate()
        timer = nil
        let points = locationManager.stopTracking()
        let distance = Self.totalDistance(points: points)
        guard points.count > 1, distance >= 100 else { return nil }

        let route = WalkRoute(
            startDate: points.first!.timestamp,
            points: points,
            distanceMeters: distance,
            durationSeconds: elapsedSeconds,
            peeCount: peeCount,
            poopCount: poopCount,
            peeSpots: peeSpots,
            poopSpots: poopSpots,
            metDogFriendIDs: Array(metFriendIDs),
            photosData: photos,
            ownerID: ownerID
        )
        route.endDate = points.last!.timestamp

        // 常走路线：命中 3 次静默收录，不弹命名弹窗。
        let candidates = (try? context.fetch(FetchDescriptor<KnownRoute>())) ?? []
        switch matcher.bestMatch(for: points, candidates: candidates) {
        case .matchedCandidate(let known, _):
            known.matchCount += 1
            if known.matchCount >= matcher.confirmMatchCount { known.confirmed = true }
            route.isKnownRoute = true
            route.matchedKnownRouteID = known.id
        case .newRoute:
            let known = KnownRoute(referencePoints: points, ownerID: ownerID)
            context.insert(known)
            route.matchedKnownRouteID = known.id
        }

        // 当天累计（含本次）是否 ≥15min 达标 —— 供「完美的一天」派生遛狗打卡。
        route.meetsDailyGoal = Self.reachesDailyGoal(context: context, addingSeconds: elapsedSeconds, on: route.startDate)

        // 遇到的狗朋友各 +1 亲密度（同一次遛狗同一只只 +1）。
        if !metFriendIDs.isEmpty {
            let friends = (try? context.fetch(FetchDescriptor<DogFriend>())) ?? []
            for f in friends where metFriendIDs.contains(f.id) { f.intimacy += 1 }
        }

        context.insert(route)
        try? context.save()
        // 落库成功就把快照清掉；下次开遛不会再问「继续」。
        InProgressWalkStore.clear()
        return route
    }

    /// 当天已有遛狗时长 + 本次是否 ≥15min。
    /// 按**归属日**取窗口（04:00–次日 04:00）：凌晨遛的狗跟前一晚算同一场。
    private static func reachesDailyGoal(context: ModelContext, addingSeconds: Int, on date: Date) -> Bool {
        let window = PetDay.attributionWindow(for: PetDay.attributionDay(for: date))
        let dayStart = window.start
        let dayEnd = window.end
        let descriptor = FetchDescriptor<WalkRoute>(
            predicate: #Predicate { $0.startDate >= dayStart && $0.startDate < dayEnd }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let priorSeconds = existing.reduce(0) { $0 + $1.durationSeconds }
        return priorSeconds + addingSeconds >= dailyGoalSeconds
    }

    private static func totalDistance(points: [RoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += b.distance(from: a)
        }
        return total
    }
}
