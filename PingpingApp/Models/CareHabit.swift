import Foundation
import SwiftData

/// 「完美的一天 · 日常」里的一个可打卡习惯（行为）。默认 5 项，可在「编辑」里增删。
@Model
final class CareHabit {
    var id: UUID
    var name: String
    var emoji: String
    /// 是否启用。完美值 % = 已完成 ÷ 已启用，只有 enabled 的习惯计入分母。
    var enabled: Bool
    /// 是否自动联动（如「遛狗」：当天有达标遛狗记录即自动打勾，不用手动点）。
    var isAuto: Bool
    var sortOrder: Int
    var ownerID: String?

    init(name: String, emoji: String, enabled: Bool = true, isAuto: Bool = false, sortOrder: Int = 0, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.enabled = enabled
        self.isAuto = isAuto
        self.sortOrder = sortOrder
        self.ownerID = ownerID
    }

    /// 首次启动时写入的默认 5 项（喂食为自动喂食器，不作打卡项）。
    static func defaults() -> [CareHabit] {
        [
            CareHabit(name: "遛狗", emoji: "🐾", isAuto: true, sortOrder: 0),
            CareHabit(name: "擦嘴擦脚", emoji: "🧼", sortOrder: 1),
            CareHabit(name: "换水", emoji: "💧", sortOrder: 2),
            CareHabit(name: "陪伴", emoji: "💛", sortOrder: 3),
            CareHabit(name: "便便观察", emoji: "💩", sortOrder: 4),
        ]
    }
}
