import Foundation
import CoreLocation

/// 收点前的质量闸门。刚开始定位的头几个点常常是基站/WiFi 粗定位，
/// horizontalAccuracy 动辄几百米 —— 直接收下就会看到狗头落在几百米外，
/// 而且那个假点会永久留在轨迹里，接出一条不存在的长边、把总里程也撑大。
/// 另外 requestLocation() 可能直接回一个缓存的旧点，所以也挡掉过期的。
///
/// 写成文件级函数（而不是 LocationManager 的 static）是故意的：
/// LocationManager 标了 @MainActor，它的 static 成员会跟着继承隔离，
/// 从 nonisolated 的 delegate 回调里调就会踩 actor 隔离错误。
private func isUsableFix(_ loc: CLLocation) -> Bool {
    loc.horizontalAccuracy >= 0                          // 负数 = 无效点
        && loc.horizontalAccuracy <= 50                  // 步行场景 50m 够用；调大更宽松，但容易收进粗定位
        && abs(loc.timestamp.timeIntervalSinceNow) <= 15 // 15s 以上算缓存点
}

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentPoints: [RoutePoint] = []
    @Published var isTracking = false
    /// 最近一次拿到的位置，跟遛狗轨迹无关。遛狗 tab 顶部那张静态地图用它摆狗头。
    @Published var lastKnownCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .fitness
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// 只在已经授权过的情况下取一次位置，绝不主动弹权限申请。
    /// 遛狗 tab 只是展示，不该因为切个 tab 就打扰用户；没授权就不显示狗头。
    func requestOneShotIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func startTracking() {
        currentPoints = []
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stopTracking() -> [RoutePoint] {
        isTracking = false
        manager.stopUpdatingLocation()
        return currentPoints
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let usable = locations.filter(isUsableFix)
        guard !usable.isEmpty else { return }
        let points = usable.map { RoutePoint(coordinate: $0.coordinate, timestamp: $0.timestamp) }
        Task { @MainActor in
            self.lastKnownCoordinate = points.last?.coordinate
            // 只有真在遛狗时才进轨迹；requestOneShotIfAuthorized 拿到的点不算数。
            guard self.isTracking else { return }
            self.currentPoints.append(contentsOf: points)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一次性取点失败就算了，地图上不显示狗头即可，没必要打扰用户。
    }
}
