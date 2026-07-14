import Foundation
import SwiftData
import CoreLocation

@MainActor
final class WalkSessionViewModel: ObservableObject {
    @Published var elapsedSeconds: Int = 0
    @Published var distanceMeters: Double = 0

    let locationManager = LocationManager()
    private let matcher = RouteMatchingService()
    private var timer: Timer?

    func start() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startTracking()
        elapsedSeconds = 0
        distanceMeters = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
    }

    func finish(context: ModelContext, ownerID: String? = nil) {
        timer?.invalidate()
        timer = nil
        let points = locationManager.stopTracking()
        guard points.count > 1 else { return }

        distanceMeters = Self.totalDistance(points: points)
        let route = WalkRoute(startDate: points.first!.timestamp, points: points, distanceMeters: distanceMeters, ownerID: ownerID)
        route.endDate = points.last!.timestamp

        let candidates = (try? context.fetch(FetchDescriptor<KnownRoute>())) ?? []

        switch matcher.bestMatch(for: points, candidates: candidates) {
        case .matchedCandidate(let known, _):
            known.matchCount += 1
            if known.matchCount >= matcher.confirmMatchCount {
                known.confirmed = true
            }
            route.isKnownRoute = true
            route.matchedKnownRouteID = known.id
        case .newRoute:
            let known = KnownRoute(referencePoints: points, ownerID: ownerID)
            context.insert(known)
            route.matchedKnownRouteID = known.id
        }

        context.insert(route)
        try? context.save()
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
