import SwiftUI
import SwiftData

struct PerfectDayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CareHabit.sortOrder) private var habits: [CareHabit]
    @Query private var logs: [DailyLog]
    @Query private var cycles: [CareCycle]
    @Query private var conditions: [HealthCondition]
    @Query private var walks: [WalkRoute]

    @State private var selectedDay: Date = PetDay.start()
    @State private var showChallenge = false
    @State private var showSettings = false

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

    /// 遛狗（自动习惯）当天是否达标：今天有遛狗记录即算完成。
    private var autoWalkDone: Bool {
        walks.contains { PetDay.start(for: $0.startDate) == selectedDay }
    }

    private func isDone(_ habit: CareHabit) -> Bool {
        if habit.isAuto { return autoWalkDone }
        return log(for: selectedDay)?.completedHabitIDs.contains(habit.id) ?? false
    }

    private var liveScore: Int {
        let done = enabledHabits.filter { isDone($0) }.count
        return PerfectDayScoring.score(
            completedCount: done, enabledCount: enabledHabits.count,
            healthOK: healthOK, cleanOK: cleanOK
        )
    }

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
                    DateStrip(days: PetDay.recentDays(14), selected: $selectedDay, tierProvider: tier(for:))
                        .padding(.top, 4)
                    ring.padding(.top, 8)
                    encouragement.padding(.top, 4)
                    bodySection.padding(.top, 24)
                    dailySection.padding(.top, 18)
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showChallenge) { ChallengeInfoSheet() }
        .sheet(isPresented: $showSettings) { PerfectDaySettingsView() }
    }

    private func tier(for day: Date) -> SunTier {
        if day == PetDay.start() { return SunTier.from(score: liveScore) }
        return log(for: day)?.sunTier ?? .gray
    }

    // MARK: - 子视图

    private var header: some View {
        HStack {
            Text("今天").font(.system(size: 28, weight: .bold)).foregroundStyle(AppTheme.ink)
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
            VStack(spacing: 2) {
                Text("\(displayScore)%").font(.system(size: 46, weight: .bold)).monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                Text("完美的一天").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.inkSub)
                Text("Perfect Day").font(.system(size: 10)).foregroundStyle(AppTheme.inkSub.opacity(0.7))
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
    }

    private var encouragement: some View {
        VStack(spacing: 6) {
            Text("🐶").font(.system(size: 34))
            Text("平平今天也在等你一起完成这一天").font(.system(size: 13)).foregroundStyle(AppTheme.inkSub)
        }
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
        if let idx = dayLog.completedHabitIDs.firstIndex(of: habit.id) {
            dayLog.completedHabitIDs.remove(at: idx)
        } else {
            dayLog.completedHabitIDs.append(habit.id)
        }
        persist(dayLog)
    }

    /// 每次打卡后重算并落库当天分数/档位/身体状态（保证进度环、日期条、历史一致）。
    private func persist(_ dayLog: DailyLog) {
        let done = enabledHabits.filter { h in
            h.isAuto ? autoWalkDone : dayLog.completedHabitIDs.contains(h.id)
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
