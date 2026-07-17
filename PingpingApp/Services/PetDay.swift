import Foundation

/// 「养宠日」边界：每天凌晨 4:00 翻篇（4 点前的凌晨遛狗算前一天）。
/// 完美的一天的 DailyLog 都以「养宠日起点」（当天 04:00）作为 date 归一化。
enum PetDay {
    static let rolloverHour = 4

    /// 给任意时刻，返回它所属养宠日的起点（该日 04:00）。
    static func start(for date: Date = .now, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        let base = hour < rolloverHour
            ? calendar.date(byAdding: .day, value: -1, to: date)!
            : date
        return calendar.date(
            bySettingHour: rolloverHour, minute: 0, second: 0, of: calendar.startOfDay(for: base)
        ) ?? calendar.startOfDay(for: base)
    }

    /// 最近 N 个养宠日的起点，从早到晚（用于日期条）。
    static func recentDays(_ count: Int, ending: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = start(for: ending, calendar: calendar)
        return (0..<count).reversed().map {
            calendar.date(byAdding: .day, value: -$0, to: today)!
        }
    }
}
