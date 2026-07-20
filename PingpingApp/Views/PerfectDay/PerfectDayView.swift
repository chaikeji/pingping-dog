import SwiftUI
import SwiftData

struct PerfectDayView: View {
    /// nil = 今天（tab 根页面，可打卡）；有值 = 历史某天（同一套 UI，但只读）。
    var day: Date? = nil
    /// 点日期条时通知外层换页。根页面和历史页共用，所以由外层决定是 push 还是横跳。
    var onSelectDay: (Date) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CareHabit.sortOrder) private var habits: [CareHabit]
    @Query private var logs: [DailyLog]
    @Query private var cycles: [CareCycle]
    @Query private var conditions: [HealthCondition]
    @Query private var walks: [WalkRoute]

    @State private var showChallenge = false
    @State private var showSettings = false

    // 打卡飞粒子：捕获环中心/习惯按钮位置，打勾时发一串 emoji 飞向中心百分比。
    @State private var anchorPoints: [String: CGPoint] = [:]
    @State private var particles: [FlyParticle] = []

    private var selectedDay: Date { day ?? PetDay.start() }
    /// 只有今天能打卡。历史一律只读 —— 事后补打卡就失去记录的意义了。
    private var isToday: Bool { selectedDay == PetDay.start() }

    // MARK: - 身体状态（决定封顶）

    private var healthOK: Bool {
        let activeDisease = conditions.contains { !$0.healed }
        let healthOverdue = cycles.contains { $0.type.category == .health && $0.isOverdue }
        return !activeDisease && !healthOverdue
    }
    private var cleanOK: Bool {
        !cycles.contains { $0.type.category == .clean && $0.isOverdue }
    }

    // MARK: - 当天日志（今天可编辑；历史只读展示已存分数）

    private var enabledHabits: [CareHabit] { habits.filter(\.enabled) }

    private func log(for day: Date) -> DailyLog? {
        logs.first { $0.date == day }
    }

    /// 某天的遛狗记录。按**归属日**算：凌晨 4 点前遛的算前一天。
    private func walkRecords(on day: Date) -> [WalkRoute] {
        walks.filter { PetDay.attributionDay(for: $0.startDate) == day }
    }

    /// 遛狗（自动习惯）当天是否达标：当天累计遛狗 ≥15 分钟（PRD §5.3 联动）。
    private func autoWalkDone(on day: Date) -> Bool {
        walkRecords(on: day).reduce(0) { $0 + $1.durationSeconds } >= WalkSessionViewModel.dailyGoalSeconds
    }

    /// 当天遛狗时有拉屎 → 自动满足「便便观察」（PRD §5.3 联动）。
    private func poopObserved(on day: Date) -> Bool {
        walkRecords(on: day).contains { $0.poopCount > 0 }
    }

    /// 「便便观察」习惯按默认名匹配；用户若改名/删除则退化为纯手动打卡。
    private func isPoopHabit(_ habit: CareHabit) -> Bool { habit.name == "便便观察" }

    /// 某习惯当天是否算完成（供进度环实时计算用）。
    private func isDone(_ habit: CareHabit) -> Bool {
        derivedDone(habit, on: selectedDay)
    }

    /// 某天某习惯是否算完成。手动打卡从那天的 DailyLog 取。
    private func derivedDone(_ habit: CareHabit, on day: Date) -> Bool {
        derivedDone(
            habit, on: day,
            manualDone: log(for: day)?.completedHabitIDs.contains(habit.id) ?? false
        )
    }

    /// 统一的完成判定：自动遛狗 / 拉屎联动 / 手动打卡三者取或。
    private func derivedDone(_ habit: CareHabit, on day: Date, manualDone: Bool) -> Bool {
        if habit.isAuto { return autoWalkDone(on: day) }             // 遛狗
        if isPoopHabit(habit) && poopObserved(on: day) { return true }  // 便便观察 ← 遛狗拉屎
        return manualDone
    }

    /// 日期条的范围：从第一条记录到今天，**至少两个月**。
    /// 不是真的无限，但 LazyHStack 撑得住，攒多久就能翻多久。
    private static let minimumStripDays = 60

    private var stripDays: [Date] {
        let today = PetDay.start()
        let earliest = logs.map(\.date).min() ?? today
        let span = (Calendar.current.dateComponents([.day], from: earliest, to: today).day ?? 0) + 1
        return PetDay.recentDays(max(span, Self.minimumStripDays))
    }

    /// 按当下的身体状态实时算某天的分。身体状态只有「现在」一个版本，
    /// 所以这个只对今天有意义；历史一律读那天存下来的。
    private func liveScore(on day: Date) -> Int {
        let done = enabledHabits.filter { derivedDone($0, on: day) }.count
        return PerfectDayScoring.score(
            completedCount: done, enabledCount: enabledHabits.count,
            healthOK: healthOK, cleanOK: cleanOK
        )
    }

    private var liveScore: Int { liveScore(on: selectedDay) }

    /// 当前进度环显示的分数：今天用实时算的，历史用存下来的。
    private var displayScore: Int {
        isToday ? liveScore : (log(for: selectedDay)?.perfectScore ?? 0)
    }

    var body: some View {
        ZStack {
            AppTheme.stageGray.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    header
                    DateStrip(days: stripDays, tierProvider: tier(for:), onSelect: onSelectDay)
                        .padding(.top, 4)
                    // 太阳是午夜换的；4:00 只管「这次遛狗算哪天」，两回事，说清楚。
                    Text("凌晨 4:00 前遛的狗，算前一天")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.inkSub.opacity(0.75))
                        .padding(.top, 5)
                    ring.padding(.top, 12)
                    bodySection.padding(.top, 28)
                    dailySection.padding(.top, 18)
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
            }
        }
        .coordinateSpace(name: "pdspace")
        .onPreferenceChange(PDAnchorKey.self) { anchorPoints = $0 }
        .overlay {
            ForEach(particles) { p in
                Text(p.emoji).font(.system(size: 20))
                    .position(p.arrived ? p.end : p.start)
                    .opacity(p.arrived ? 0 : 1)
                    .scaleEffect(p.arrived ? 0.4 : 1)
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showChallenge) { ChallengeInfoSheet() }
        .sheet(isPresented: $showSettings) { PerfectDaySettingsView() }
        .task { syncLogs() }
    }

    /// 打勾时从习惯按钮发一串该习惯的 emoji，飞向进度环中心的百分比，到达后消失。
    private func spawnParticles(for habit: CareHabit) {
        guard let start = anchorPoints["h-\(habit.id.uuidString)"],
              let end = anchorPoints["ring"] else { return }
        let batch = (0..<6).map { _ in
            FlyParticle(
                emoji: habit.emoji,
                start: CGPoint(x: start.x + .random(in: -8...8), y: start.y + .random(in: -8...8)),
                end: CGPoint(x: end.x + .random(in: -14...14), y: end.y + .random(in: -14...14))
            )
        }
        particles.append(contentsOf: batch)
        let ids = Set(batch.map(\.id))
        withAnimation(.easeInOut(duration: 0.65)) {
            for i in particles.indices where ids.contains(particles[i].id) { particles[i].arrived = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            particles.removeAll { ids.contains($0.id) }
        }
    }

    /// 打开页面时把自动完成（遛狗达标 / 拉屎联动）落库，
    /// 保证遛狗后不手动打卡也能更新分数（供日期条 & 以后的通知引擎读取）。
    ///
    /// 昨天也重算一遍：凌晨 4 点前遛的狗算昨天的，那笔账得过了午夜才落得下来。
    private func syncLogs() {
        guard isToday else { return }  // 历史页只读，不写库
        normalizeLegacyLogDates()

        let today = PetDay.start()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        var days = [today]
        // 昨天只在真发生过事情时才补记，别给没打开过 App 的日子凭空造记录。
        if log(for: yesterday) != nil || !walkRecords(on: yesterday).isEmpty {
            days.insert(yesterday, at: 0)
        }

        for target in days {
            let dayLog: DailyLog
            if let existing = log(for: target) {
                dayLog = existing
            } else {
                dayLog = DailyLog(date: target)
                context.insert(dayLog)
            }
            persist(dayLog)
        }
        try? context.save()
    }

    /// 日期边界从 04:00 改成午夜之前存的记录，date 停在 04:00，按精确相等再也找不到。
    /// 就地归一到午夜；万一同一天撞出两条，把打卡并进早的那条，删掉多的。
    private func normalizeLegacyLogDates() {
        let calendar = Calendar.current
        var byDay: [Date: DailyLog] = [:]
        for entry in logs.sorted(by: { $0.date < $1.date }) {
            let normalized = calendar.startOfDay(for: entry.date)
            if let kept = byDay[normalized] {
                kept.completedHabitIDs = Array(Set(kept.completedHabitIDs + entry.completedHabitIDs))
                context.delete(entry)
            } else {
                if entry.date != normalized { entry.date = normalized }
                byDay[normalized] = entry
            }
        }
    }

    private func tier(for day: Date) -> SunTier {
        // 「今天」那颗永远按今天实时算 —— 不能用 liveScore，
        // 在历史页上它算的是那个历史日，会把今天的太阳画错。
        if day == PetDay.start() { return SunTier.from(score: liveScore(on: day)) }
        return log(for: day)?.sunTier ?? .gray
    }

    // MARK: - 子视图

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private var header: some View {
        HStack(spacing: 10) {
            // 历史页自己画返回键：导航栏是藏起来的，这样两个页面长得一模一样。
            if !isToday {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
            }
            Text(isToday ? "今天" : Self.headerFormatter.string(from: selectedDay))
                .font(.system(size: 28, weight: .bold)).foregroundStyle(AppTheme.ink)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(AppTheme.ink)
            }
        }
        .padding(.top, 8)
    }

    private var ring: some View {
        ZStack {
            ProgressRing(percent: displayScore)
                .frame(width: 220, height: 220)
                // 狗头坐进 270° 弧底部那个 90° 缺口的正中间：缺口中心在正下方、半径 110 处，
                // 也就是这个 220×220 frame 的底边。.bottom 对齐让图的底边贴到那条线上，
                // 再往下挪半个身位（44 的一半 = 22）才是「中心压在线上」。
                .overlay(alignment: .bottom) {
                    Image("dog_head").resizable().scaledToFit()
                        .frame(width: 44, height: 44)
                        .offset(y: 22)
                }
            // 环内自上而下：小太阳徽章 → 大号百分比（狗头已挪到下方缺口里）
            VStack(spacing: 2) {
                SunBadge(tier: SunTier.from(score: displayScore))
                    .frame(width: 30, height: 30)
                Text("\(displayScore)%").font(.system(size: 46, weight: .bold)).monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: PDAnchorKey.self, value: ["ring": g.frame(in: .named("pdspace")).center])
                    })
            }
        }
        .overlay(alignment: .leading) {
            Button { showChallenge = true } label: {
                Image(systemName: "info.circle").font(.system(size: 20)).foregroundStyle(AppTheme.inkSub)
            }
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(AppTheme.inkSub.opacity(0.5))
        }
        .padding(.horizontal, 8)
        // 狗头有 22pt 探出环的 frame，overlay 不占布局，这里补回来免得压到下面的内容。
        .padding(.bottom, 22)
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("身体", editAction: { showSettings = true })
            statusRow(title: "健康", ok: healthOK, okText: "无异常", badText: "有疾病或驱虫/体检逾期")
            statusRow(title: "清洁", ok: cleanOK, okText: "都到位", badText: "剪指甲/清耳/刷牙有逾期")
            Text("身体不达标的日子，完美值最高只到银/铜")
                .font(.system(size: 11)).foregroundStyle(AppTheme.inkSub.opacity(0.8))
        }
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("日常", editAction: { showSettings = true })
            ForEach(enabledHabits) { habit in
                habitRow(habit)
            }
        }
    }

    private func sectionHeader(_ title: String, editAction: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(AppTheme.ink)
            Spacer()
            Button("编辑", action: editAction).font(.system(size: 13)).foregroundStyle(AppTheme.inkSub)
        }
    }

    private func statusRow(title: String, ok: Bool, okText: String, badText: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? AppTheme.greenOK : AppTheme.coral)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.ink)
            Spacer()
            Text(ok ? okText : badText).font(.system(size: 12)).foregroundStyle(AppTheme.inkSub)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func habitRow(_ habit: CareHabit) -> some View {
        let done = isDone(habit)
        return HStack(spacing: 12) {
            Text(habit.emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name).font(.system(size: 14.5, weight: .bold))
                    .strikethrough(done).foregroundStyle(AppTheme.ink)
                if habit.isAuto {
                    Text("有遛狗记录自动打勾").font(.system(size: 11)).foregroundStyle(AppTheme.inkSub)
                }
            }
            Spacer()
            Button {
                toggle(habit)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(done ? AppTheme.greenOK : AppTheme.inkSub.opacity(0.4))
            }
            .disabled(habit.isAuto || !isToday)  // 自动习惯 & 历史日不可手动点
            .background(GeometryReader { g in
                Color.clear.preference(key: PDAnchorKey.self, value: ["h-\(habit.id.uuidString)": g.frame(in: .named("pdspace")).center])
            })
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(done ? 0.7 : 1)
    }

    // MARK: - 打卡逻辑

    private func toggle(_ habit: CareHabit) {
        guard isToday, !habit.isAuto else { return }
        let today = PetDay.start()
        let dayLog: DailyLog
        if let existing = log(for: today) {
            dayLog = existing
        } else {
            dayLog = DailyLog(date: today)
            context.insert(dayLog)
        }
        var turnedOn = false
        if let idx = dayLog.completedHabitIDs.firstIndex(of: habit.id) {
            dayLog.completedHabitIDs.remove(at: idx)
        } else {
            dayLog.completedHabitIDs.append(habit.id)
            turnedOn = true
        }
        persist(dayLog)
        if turnedOn { spawnParticles(for: habit) }
    }

    /// 每次打卡后重算并落库当天分数/档位/身体状态（保证进度环、日期条、历史一致）。
    private func persist(_ dayLog: DailyLog) {
        let done = enabledHabits.filter { h in
            derivedDone(h, on: dayLog.date, manualDone: dayLog.completedHabitIDs.contains(h.id))
        }.count
        let score = PerfectDayScoring.score(
            completedCount: done, enabledCount: enabledHabits.count,
            healthOK: healthOK, cleanOK: cleanOK
        )
        dayLog.healthOK = healthOK
        dayLog.cleanOK = cleanOK
        dayLog.perfectScore = score
        dayLog.sunTier = SunTier.from(score: score)
    }
}

/// 一颗飞行的 emoji 粒子。
private struct FlyParticle: Identifiable {
    let id = UUID()
    let emoji: String
    let start: CGPoint
    let end: CGPoint
    var arrived = false
}

/// 收集环中心 / 各习惯按钮在 "pdspace" 坐标系里的位置。
private struct PDAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
