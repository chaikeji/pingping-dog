import Foundation
import SwiftData

/// 常走路线库（PRD §4.3 v1.5）。命中 3 次即静默收录，**不再命名**（去掉了命名弹窗）。
@Model
final class KnownRoute {
    var id: UUID
    var referencePointsData: Data
    var matchCount: Int
    var confirmed: Bool
    var ownerID: String?

    @Transient
    var referencePoints: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: referencePointsData)) ?? [] }
        set { referencePointsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(referencePoints: [RoutePoint], ownerID: String? = nil) {
        self.id = UUID()
        self.referencePointsData = (try? JSONEncoder().encode(referencePoints)) ?? Data()
        self.matchCount = 1
        self.confirmed = false
        self.ownerID = ownerID
    }
}
