import Foundation

/// 首页状态通知的一条待展示项（PRD §5.1）。由护理/健康/遛狗状态派生，按优先级轮播。
struct StatusNotification: Identifiable, Equatable {
    enum Category { case acuteHealth, walk, care }

    let id: String
    let text: String
    /// 优先级：数字越小越靠前（急性健康 0 ＞ 遛狗 1 ＞ 周期护理 2）。
    let priority: Int
    /// 同档内的次级排序权重（逾期越久越靠前）。
    let overdueDays: Int
    let category: Category
}

/// 通知引擎：把 CareCycle / HealthCondition / WalkRoute 的状态派生成排好序的待展示项。
/// PRD §5.1 优先级：急性健康 ＞ 日常必需(遛狗) ＞ 周期护理；同档内逾期越久越靠前。
enum NotificationEngine {
    /// 遛狗提醒阈值：超过 24h 没遛狗。
    static let walkReminderHours = 24

    static func build(
        cycles: [CareCycle],
        conditions: [HealthCondition],
        walks: [WalkRoute],
        now: Date = .now
    ) -> [StatusNotification] {
        var items: [StatusNotification] = []

        // 0) 急性健康：每个未痊愈的疾病
        for c in conditions where !c.healed {
            items.append(StatusNotification(
                id: "cond-\(c.id.uuidString)",
                text: "平平有「\(c.name)」还没好，多留意一下",
                priority: 0, overdueDays: 0, category: .acuteHealth
            ))
        }

        // 1) 遛狗：超过 24h（含从未遛过）
        let lastWalk = walks.map(\.startDate).max()
        let hoursSince = lastWalk.map { now.timeIntervalSince($0) / 3600 }
        if hoursSince == nil || hoursSince! >= Double(walkReminderHours) {
            let text: String
            if let h = hoursSince {
                text = "平平已经 \(Int(h)) 小时没遛狗了，去遛遛 ta 吧"
            } else {
                text = "还没有遛狗记录，带平平出门走走吧"
            }
            items.append(StatusNotification(
                id: "walk", text: text,
                priority: 1, overdueDays: Int((hoursSince ?? 0) / 24), category: .walk
            ))
        }

        // 2) 周期护理：每个逾期的护理项
        for cyc in cycles where cyc.isOverdue {
            let days = overdueDays(of: cyc, now: now)
            let text = days > 0
                ? "「\(cyc.type.displayName)」已逾期 \(days) 天，该做啦"
                : "「\(cyc.type.displayName)」还没登记过，去设置里补一下"
            items.append(StatusNotification(
                id: "cycle-\(cyc.type.rawValue)",
                text: text, priority: 2, overdueDays: days, category: .care
            ))
        }

        // 优先级升序；同档内逾期越久越靠前
        return items.sorted { a, b in
            a.priority != b.priority ? a.priority < b.priority : a.overdueDays > b.overdueDays
        }
    }

    /// 护理项逾期了多少天（未登记「上次完成日」返回 0，另有文案处理）。
    private static func overdueDays(of cycle: CareCycle, now: Date) -> Int {
        guard let last = cycle.lastDoneDate else { return 0 }
        let due = Calendar.current.date(byAdding: .day, value: cycle.cycleDays, to: last) ?? last
        let secs = now.timeIntervalSince(due)
        return secs > 0 ? Int(secs / 86_400) : 0
    }
}
