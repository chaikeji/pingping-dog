import Foundation
import SwiftData

@Model
final class WalkRoute {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var pointsData: Data
    var distanceMeters: Double
    var isKnownRoute: Bool
    var matchedKnownRouteID: UUID?
    var ownerID: String?

    @Transient
    var points: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: pointsData)) ?? [] }
        set { pointsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(startDate: Date = .now, points: [RoutePoint] = [], distanceMeters: Double = 0, ownerID: String? = nil) {
        self.id = UUID()
        self.startDate = startDate
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.distanceMeters = distanceMeters
        self.isKnownRoute = false
        self.ownerID = ownerID
    }
}
