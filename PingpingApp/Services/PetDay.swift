import Foundation

/// 日期边界。这里有**两套**，别混：
///
/// - **日期身份**（`start`）：午夜翻篇，跟手机日历一致。过了 0:00 就是新的一天、
///   新的太阳、新的空白成绩单。日期条和 DailyLog.date 都用这个。
/// - **活动归属**（`attributionDay`）：凌晨 4 点前发生的事算前一天的战果。
///   半夜 1 点遛完狗回来，那是「昨天」的遛狗，不该记到刚开始的这一天头上。
///
/// 以前两件事共用一个 4:00 边界，副作用是过了午夜迟迟不出新太阳，看着像坏了。
enum PetDay {
    /// 活动归属的分界钟点：这个点之前算前一天。
    static let attributionCutoffHour = 4

    /// 某个时刻属于哪一天（日期身份，午夜翻篇）。
    static func start(for date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 一次活动（遛狗等）该记到哪一天：凌晨 4 点前算前一天。
    static func attributionDay(for date: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        let base = hour < attributionCutoffHour
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
            : date
        return calendar.startOfDay(for: base)
    }

    /// 某一天对应的真实时间窗 `[当天 04:00, 次日 04:00)`，用来按归属日捞记录。
    static func attributionWindow(
        for day: Date, calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .hour, value: attributionCutoffHour, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    /// 最近 N 天，从早到晚（用于日期条）。
    static func recentDays(_ count: Int, ending: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = start(for: ending, calendar: calendar)
        return (0..<count).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }
}
