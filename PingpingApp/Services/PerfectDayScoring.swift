import Foundation

/// 完美的一天计分（纯函数，无副作用）。规则见 PRD §5.4。
enum PerfectDayScoring {
    /// 当天完美值 % = 已完成习惯 ÷ 已启用习惯（等权），再按身体状态封顶。
    /// - 健康、清洁都 ok → 不封顶（可达 100）
    /// - 任一不 ok → 上限 79（最高银）
    /// - 都不 ok → 上限 59（最高铜）
    static func score(completedCount: Int, enabledCount: Int, healthOK: Bool, cleanOK: Bool) -> Int {
        guard enabledCount > 0 else { return 0 }
        let raw = Int((Double(completedCount) / Double(enabledCount) * 100).rounded())
        let ceiling: Int
        switch (healthOK, cleanOK) {
        case (true, true): ceiling = 100
        case (false, false): ceiling = 59
        default: ceiling = 79
        }
        return min(raw, ceiling)
    }
}
