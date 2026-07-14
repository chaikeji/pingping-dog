import Foundation
import SwiftData

@Model
final class KnownRoute {
    var id: UUID
    var name: String
    var referencePointsData: Data
    var matchCount: Int
    var confirmed: Bool
    var ownerID: String?

    @Transient
    var referencePoints: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: referencePointsData)) ?? [] }
        set { referencePointsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(name: String = "未命名路线", referencePoints: [RoutePoint], ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.referencePointsData = (try? JSONEncoder().encode(referencePoints)) ?? Data()
        self.matchCount = 1
        self.confirmed = false
        self.ownerID = ownerID
    }
}
