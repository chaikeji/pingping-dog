import Foundation
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentPoints: [RoutePoint] = []
    @Published var isTracking = false

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
            self.currentPoints.append(contentsOf: points)
        }
    }
}
