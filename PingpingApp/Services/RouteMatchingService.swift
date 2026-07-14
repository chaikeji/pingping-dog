import Foundation
import CoreLocation

enum RouteMatchResult {
    case newRoute
    case matchedCandidate(KnownRoute, overlap: Double)
}

struct RouteMatchingService {
    var overlapThreshold: Double = 0.9
    var corridorRadiusMeters: Double = 30
    var confirmMatchCount: Int = 3

    func overlapRatio(of route: [RoutePoint], against reference: [RoutePoint]) -> Double {
        guard !route.isEmpty, !reference.isEmpty else { return 0 }
        let referenceLocations = reference.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let withinCorridor = route.filter { point in
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return referenceLocations.contains { $0.distance(from: location) <= corridorRadiusMeters }
        }
        return Double(withinCorridor.count) / Double(route.count)
    }

    func bestMatch(for route: [RoutePoint], candidates: [KnownRoute]) -> RouteMatchResult {
        var best: (KnownRoute, Double)?
        for candidate in candidates {
            let ratio = overlapRatio(of: route, against: candidate.referencePoints)
            if ratio >= overlapThreshold, (best == nil || ratio > best!.1) {
                best = (candidate, ratio)
            }
        }
        if let best {
            return .matchedCandidate(best.0, overlap: best.1)
        }
        return .newRoute
    }
}
