import Foundation
import CoreLocation

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
        let points = locations.map { RoutePoint(coordinate: $0.coordinate, timestamp: $0.timestamp) }
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
