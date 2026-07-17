import Foundation
import SwiftData
import CoreLocation

/// 一次遛狗会话的状态（PRD §5.3）。记录距离/时长，以及尿尿/拉屎/遇到的狗朋友/拍照；
/// 支持暂停（暂停不计时）。结束时静默识别常走路线、给遇到的狗朋友 +1 亲密度、算当天是否达标。
@MainActor
final class WalkSessionViewModel: ObservableObject {
    @Published var elapsedSeconds: Int = 0        // 有效计时（扣掉暂停）
    @Published var distanceMeters: Double = 0
    @Published var isPaused = false
    @Published var peeCount = 0
    @Published var poopCount = 0
    @Published var metFriendIDs: Set<UUID> = []
    @Published var photos: [Data] = []

    let locationManager = LocationManager()
    private let matcher = RouteMatchingService()
    private var timer: Timer?

    /// 当天累计达标阈值：15 分钟。
    static let dailyGoalSeconds = 15 * 60

    var isTracking: Bool { locationManager.isTracking }

    func start() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startTracking()
        elapsedSeconds = 0
        distanceMeters = 0
        isPaused = false
        peeCount = 0
        poopCount = 0
        metFriendIDs = []
        photos = []
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.elapsedSeconds += 1
                self.distanceMeters = Self.totalDistance(points: self.locationManager.currentPoints)
            }
        }
    }

    func togglePause() { isPaused.toggle() }
    func addPee() { peeCount += 1 }
    func addPoop() { poopCount += 1 }
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
        return route
    }

    /// 当天（养宠日 04:00 翻篇）已有遛狗时长 + 本次是否 ≥15min。
    private static func reachesDailyGoal(context: ModelContext, addingSeconds: Int, on date: Date) -> Bool {
        let dayStart = PetDay.start(for: date)
        let dayEnd = PetDay.start(for: date.addingTimeInterval(86_400))
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
