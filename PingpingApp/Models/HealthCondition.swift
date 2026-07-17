import Foundation
import SwiftData

/// 手动登记 / 同步的疾病。存在活跃疾病（未痊愈）→ healthOK=false；
/// 同时供首页「今日状态可视化」引线标注取用。
@Model
final class HealthCondition {
    var id: UUID
    var name: String
    var foundDate: Date
    var healed: Bool
    var ownerID: String?

    init(name: String, foundDate: Date = .now, healed: Bool = false, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.foundDate = foundDate
        self.healed = healed
        self.ownerID = ownerID
    }
}
