import SwiftUI
import SwiftData
import CoreLocation

// MARK: - 让 WalkRoute 能给 navigationDestination(item:) 用
//
// SwiftData 的 @Model 会合成 var id，但不自动 conform Identifiable。
// 这里补一下，路由传递 route 实例才不用外套一层包装类型。
extension WalkRoute: Identifiable {}

/// 遛狗「累计总览 + 按月倒序」页（PRD v2）。
/// 从 WalkHistoryView 的「N月回顾」卡片点进来，是原 MonthlyDetailView 的替代品。
///
/// 页结构（自上而下）：
/// 1. 顶部大卡：累计公里 + 平均遛狗时长 + 总尿量 + 总次数 + 平均里程 + 连续遛狗周；右侧一列水杯 emoji 占位
/// 2. 每年一段小灰标；当前月永远置顶（即使 0 次）
/// 3. 每月段：段头 (N月回顾 / N 次) → 大月历 (格中画那天最长一次的路线) → 段脚 (总公里 / N月遛狗小结)
/// 4. 点日期格：当天 1 次直接跳详情；≥2 次弹底 sheet 让用户选一条
///
/// 单次详情页 (WalkDetailPlaceholder) 是临时桩子，下轮换成真页。
struct WalkAllStatsView: View {
    @Query(sort: \WalkRoute.startDate, order: .reverse) private var routes: [WalkRoute]

    /// 点日期格且当天 ≥2 次遛狗时，装当天的日期和候选列表。
    @State private var multiWalkDay: MultiWalkDay?
    /// 从「1 次直跳」或「多次选一条」之后要 push 出去的详情目标。
    @State private var pendingDetail: WalkRoute?
    /// 弹窗关闭之后再触发 push —— 避开 SwiftUI「同时呈现 sheet 和 push」的冲突。
    @State private var pendingAfterDismiss: WalkRoute?

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 20) {
                    HeroStatsCard(routes: routes)
                    ForEach(monthSections) { section in
                        MonthSection(
                            section: section,
                            onDayTap: { day in handleDayTap(day: day, in: section) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $multiWalkDay, onDismiss: {
            // 弹窗关掉之后再 push 详情；直接同 tick set 会撞「already presenting」。
            if let w = pendingAfterDismiss {
                pendingAfterDismiss = nil
                pendingDetail = w
            }
        }) { day in
            DayMultiWalkSheet(day: day) { picked in
                pendingAfterDismiss = picked
                multiWalkDay = nil
            }
        }
        .navigationDestination(item: $pendingDetail) { walk in
            WalkDetailPlaceholder(walk: walk)
        }
    }

    // MARK: 按月归组

    private var monthSections: [MonthSectionData] {
        let cal = Calendar.current
        var byKey: [String: [WalkRoute]] = [:]
        for r in routes {
            let c = cal.dateComponents([.year, .month], from: r.startDate)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            byKey[key, default: []].append(r)
        }
        // 当前月永远显示，哪怕 0 次。
        let nowC = cal.dateComponents([.year, .month], from: .now)
        let nowKey = String(format: "%04d-%02d", nowC.year ?? 0, nowC.month ?? 0)
        if byKey[nowKey] == nil { byKey[nowKey] = [] }

        var result: [MonthSectionData] = []
        var lastYear: Int? = nil
        for key in byKey.keys.sorted(by: >) {
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let y = Int(parts[0]),
                  let m = Int(parts[1]) else { continue }
            let dc = DateComponents(year: y, month: m)
            let routesInMonth = byKey[key] ?? []
            result.append(MonthSectionData(
                id: key,
                month: dc,
                routes: routesInMonth,
                showYearHeader: lastYear != y
            ))
            lastYear = y
        }
        return result
    }

    // MARK: 交互

    private func handleDayTap(day: Int, in section: MonthSectionData) {
        let walksThatDay = section.routes.filter {
            Calendar.current.component(.day, from: $0.startDate) == day
        }
        if walksThatDay.count == 1 {
            pendingDetail = walksThatDay.first
        } else if walksThatDay.count >= 2 {
            let cal = Calendar.current
            let date = cal.date(from: DateComponents(
                year: section.month.year,
                month: section.month.month,
                day: day
            )) ?? .now
            multiWalkDay = MultiWalkDay(id: date, walks: walksThatDay.sorted { $0.startDate > $1.startDate })
        }
        // 0 次的日子不响应。
    }
}

// MARK: - 每月段的数据模型

private struct MonthSectionData: Identifiable {
    let id: String
    let month: DateComponents
    let routes: [WalkRoute]
    let showYearHeader: Bool
}

private struct MultiWalkDay: Identifiable {
    let id: Date
    let walks: [WalkRoute]
    var date: Date { id }
}

// MARK: - Hero: 累计总览大卡

private struct HeroStatsCard: View {
    let routes: [WalkRoute]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // LEFT：大数字 + 2×2 stat 网格。
            // 网格用两个 VStack 竖着排 —— col1 = 平均遛狗时长 / 遛狗总次数，
            // col2 = 总尿量 / 平均里程；两列各自 leading 对齐，
            // 总尿量 和 平均里程 自然落到同一 x（spec：「要对齐」）。
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", totalKm))
                        .font(.system(size: 56, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Panora.textPrimary)
                    Text("总公里")
                        .font(.system(size: 12))
                        .foregroundStyle(Panora.textSecondary)
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        statCell(avgDurationText, "平均遛狗时长")
                        statCell("\(routes.count)", "遛狗总次数")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        statCell(totalPeeText, "总尿量")
                        statCell(String(format: "%.1f 公里", avgKm), "平均里程")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // RIGHT：牛奶柱 + 药丸 + 一周单元。
            // spec：一周在牛奶下面，跟左侧 Row3（平均里程）差不多齐平；
            // 牛奶太高会跟一周挤到 → 上移，上移越顶再减一杯 → 保守默认 3 杯，
            // 3×36 - 2×14 = 80pt + pill 24 + Spacer(≥14) + 一周 cell ~40 ≈ 158pt，
            // 左列 56+2+18+2×35+14 ≈ 165pt，塞得下不越顶。
            // 中间的 Spacer(minLength: 14) 保证至少 14pt 呼吸，
            // 左列真的更高时会撑到把一周推到跟 平均里程 同一高度。
            VStack(alignment: .leading, spacing: 6) {
                VStack(spacing: -14) {
                    ForEach(0..<3, id: \.self) { _ in
                        Text("🥛").font(.system(size: 36))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text("≈\(cupCount) 杯")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Panora.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 14)
                statCell("\(streakWeeks) 周", "连续遛狗")
            }
            .frame(width: 90)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panoraCard()
    }

    // MARK: 组件

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 计算

    private var totalKm: Double {
        routes.reduce(0) { $0 + $1.distanceMeters } / 1000
    }

    private var avgKm: Double {
        routes.isEmpty ? 0 : totalKm / Double(routes.count)
    }

    private var avgDurationText: String {
        guard !routes.isEmpty else { return "0 分" }
        let totalSec = routes.reduce(0) { $0 + $1.durationSeconds }
        let minutes = Int(round(Double(totalSec) / Double(routes.count) / 60))
        return "\(minutes) 分"
    }

    /// 单次遛狗按 140ml 估（雪纳瑞标准，多次尿尿累加）。
    private var totalPeeMl: Int { routes.count * 140 }

    private var totalPeeText: String {
        let ml = totalPeeMl
        if ml < 10000 {
            return "\(ml) ml"
        } else {
            return String(format: "%.1f 万 ml", Double(ml) / 10000)
        }
    }

    /// 一个水杯 330ml。0 次时显示 0 杯。
    private var cupCount: Int {
        Int(round(Double(totalPeeMl) / 330.0))
    }

    /// 宽松 a：从本周往回数，每周只要 ≥1 次遛狗就算 1 周，断档就停。
    private var streakWeeks: Int {
        let cal = Calendar.current
        var count = 0
        guard var week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        while true {
            let hasWalk = routes.contains { $0.startDate >= week.start && $0.startDate < week.end }
            if hasWalk {
                count += 1
                guard let prevDay = cal.date(byAdding: .weekOfYear, value: -1, to: week.start),
                      let prevInterval = cal.dateInterval(of: .weekOfYear, for: prevDay) else { break }
                week = prevInterval
            } else {
                break
            }
        }
        return count
    }
}

// MARK: - 每月段

private struct MonthSection: View {
    let section: MonthSectionData
    let onDayTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if section.showYearHeader {
                Text("\(String(format: "%d", section.month.year ?? 0))年")
                    .font(.system(size: 12))
                    .foregroundStyle(Panora.textMuted)
            }
            HStack {
                Text("\(section.month.month ?? 0)月回顾")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Panora.textPrimary)
                Spacer()
                Text("\(section.routes.count) 次")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Panora.greenOK)
            }
            RouteThumbCalendar(
                month: section.month,
                routes: section.routes,
                onDayTap: onDayTap
            )
            HStack {
                Text(String(format: "总公里 %.1f", monthKm))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Panora.textSecondary)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(section.month.month ?? 0)月遛狗小结")
                    Text("›")
                }
                .font(.system(size: 12))
                .foregroundStyle(Panora.textMuted)
            }
        }
    }

    private var monthKm: Double {
        section.routes.reduce(0) { $0 + $1.distanceMeters } / 1000
    }
}

// MARK: - 带路线缩略图的大月历

private struct RouteThumbCalendar: View {
    let month: DateComponents
    let routes: [WalkRoute]
    let onDayTap: (Int) -> Void

    // 按日聚合当月的 routes，dayCell 里 O(1) 拿
    private var byDay: [Int: [WalkRoute]] {
        var m: [Int: [WalkRoute]] = [:]
        for r in routes {
            let d = Calendar.current.component(.day, from: r.startDate)
            m[d, default: []].append(r)
        }
        return m
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { s in
                    Text(s)
                        .font(.system(size: 10))
                        .foregroundStyle(Panora.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
                ForEach(1...daysInMonth, id: \.self) { day in
                    dayCell(day: day)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let walksThatDay = byDay[day] ?? []
        if walksThatDay.isEmpty {
            // 未遛：数字居中，灰
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                Text("\(day)")
                    .font(.system(size: 12))
                    .foregroundStyle(Panora.textMuted)
            }
        } else {
            // 遛过：整格按钮 → 交给父视图处理跳单条 / 弹多条
            Button { onDayTap(day) } label: {
                dayContent(walks: walksThatDay)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func dayContent(walks: [WalkRoute]) -> some View {
        // 有多次时取「距离最长」那次画。
        let longest = walks.max(by: { $0.distanceMeters < $1.distanceMeters })
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
            if let longest, !longest.points.isEmpty {
                RouteSketch(points: longest.points)
                    .stroke(Panora.greenOK,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .padding(4)
            } else {
                // 走过但没坐标（老数据或空 points）：灰方块占位。
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .padding(8)
            }
        }
    }

    private var daysInMonth: Int {
        let cal = Calendar.current
        let date = cal.date(from: month) ?? .now
        return cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// 当月 1 号是周几（周一为第一列）。
    private var leadingBlanks: Int {
        let cal = Calendar.current
        guard let first = cal.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else { return 0 }
        let weekday = cal.component(.weekday, from: first)  // 周日=1
        return (weekday + 5) % 7  // 转成周一=0
    }
}

// MARK: - 把 [RoutePoint] 画成缩略线的 Shape
//
// 用等距柱状投影：先取 lat/lon 包围盒，按 rect 的宽高比取小的那个 scale
// 保持形状不变形；再居中留出 ~15% padding，形状不贴边。
private struct RouteSketch: Shape {
    let points: [RoutePoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }

        // 避免除零（单点或极短轨迹）。
        let latSpan: Double = max(maxLat - minLat, 0.00001)
        let lonSpan: Double = max(maxLon - minLon, 0.00001)

        // 画布保留 15% 内边距，走极端也不贴到圆角。
        let usableW: CGFloat = rect.width * 0.85
        let usableH: CGFloat = rect.height * 0.85
        let scale: CGFloat = min(usableW / lonSpan, usableH / latSpan)
        let effW: CGFloat = CGFloat(lonSpan) * scale
        let effH: CGFloat = CGFloat(latSpan) * scale
        let xOffset: CGFloat = rect.midX - effW / 2
        let yOffset: CGFloat = rect.midY - effH / 2

        for (i, p) in points.enumerated() {
            let x: CGFloat = xOffset + CGFloat(p.longitude - minLon) * scale
            // 屏幕 y 朝下，纬度朝上；用 (maxLat - p.lat) 翻一下。
            let y: CGFloat = yOffset + CGFloat(maxLat - p.latitude) * scale
            let pt = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }
}

// MARK: - 当日多次遛狗弹窗

private struct DayMultiWalkSheet: View {
    let day: MultiWalkDay
    let onSelect: (WalkRoute) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Panora.appBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(day.walks) { walk in
                            Button { onSelect(walk) } label: {
                                row(walk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Panora.textSecondary)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        let cal = Calendar.current
        let m = cal.component(.month, from: day.date)
        let d = cal.component(.day, from: day.date)
        return "\(m)月\(d)日"
    }

    private func row(_ walk: WalkRoute) -> some View {
        HStack(spacing: 12) {
            thumbnail(walk)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(rowTitle(walk))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Panora.textPrimary)
                    .lineLimit(1)
                Text(statsLine(walk))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Panora.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panoraCard()
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func thumbnail(_ walk: WalkRoute) -> some View {
        if walk.points.isEmpty {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.12))
                .padding(12)
        } else {
            RouteSketch(points: walk.points)
                .stroke(Panora.greenOK,
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .padding(8)
        }
    }

    private func rowTitle(_ walk: WalkRoute) -> String {
        let hour = Calendar.current.component(.hour, from: walk.startDate)
        return "\(weekdayText(walk.startDate)) · \(timeSlot(hour: hour))"
    }

    private func timeSlot(hour: Int) -> String {
        switch hour {
        case 5..<11: return "早上"
        case 11..<14: return "中午"
        case 14..<18: return "下午"
        case 18..<22: return "晚上"
        default: return "深夜"
        }
    }

    private func weekdayText(_ date: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let w = Calendar.current.component(.weekday, from: date)
        return names[max(0, min(w - 1, 6))]
    }

    private func statsLine(_ walk: WalkRoute) -> String {
        let km = walk.distanceMeters / 1000
        let dur = walk.durationSeconds
        let h = dur / 3600
        let m = (dur % 3600) / 60
        let s = dur % 60
        let paceMin: Int
        let paceSec: Int
        if km >= 0.01 {
            let paceSecondsPerKm = Double(dur) / km
            paceMin = Int(paceSecondsPerKm) / 60
            paceSec = Int(paceSecondsPerKm) % 60
        } else {
            paceMin = 0
            paceSec = 0
        }
        return String(format: "%.2f 公里  %02d:%02d:%02d  %02d'%02d\"", km, h, m, s, paceMin, paceSec)
    }
}

// MARK: - 单次详情临时占位（下轮换真页）

/// 图一 PRD 已定，UI 下轮实现。现在只显示关键数字，让点击流可测。
private struct WalkDetailPlaceholder: View {
    let walk: WalkRoute

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("单次遛狗详情")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Panora.textPrimary)
                Text("PRD 已定，界面下轮实现")
                    .font(.system(size: 13))
                    .foregroundStyle(Panora.textSecondary)
                Text(walk.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(Panora.textMuted)
                    .padding(.top, 12)
                Text(String(format: "%.2f 公里 · %d 分",
                            walk.distanceMeters / 1000,
                            walk.durationSeconds / 60))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Panora.textMuted)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}
