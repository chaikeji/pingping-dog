import SwiftUI
import SwiftData
import CoreLocation

/// 遛狗 Tab（PRD §5.3，Panora 深色玻璃风 Batch 1）：「开遛 + 统计」合成一页。
/// 上：地图（狗站在定位）+ 玻璃总览条 + 荧光绿「开遛！」按钮叠在地图上；
/// 下：里程卡（点开月卡回顾）+ 月度回顾卡（点开月详情）+ 最近遛狗列表。
struct WalkHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WalkRoute.startDate, order: .reverse) private var routes: [WalkRoute]
    @State private var isWalking = false
    /// 只读一次位置的轻量定位器，不申请权限（见 requestOneShotIfAuthorized）。
    @StateObject private var locator = LocationManager()
    @State private var showMonthlyDetail = false
    @State private var showMonthlyGallery = false
    /// 两张统计卡里较高一张的高度（PreferenceKey 测量），另一张同步撑到这个高度。
    @State private var maxStatCardHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Panora.appBackground.ignoresSafeArea()

                List {
                    Section {
                        statsRow
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        recentSectionHeader
                            .listRowInsets(EdgeInsets(top: 12, leading: 18, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        if routes.isEmpty {
                            Text("还没有记录，点地图上的「开遛！」开始第一次遛狗")
                                .font(.caption)
                                .foregroundStyle(Panora.textMuted)
                                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(routes.prefix(10).map { $0 }) { route in
                                recordRow(route)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                            .onDelete(perform: deleteRecent)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // 地图放在 List 的 top safeAreaInset 里，顶到屏幕最上、盖过状态栏。
                .safeAreaInset(edge: .top, spacing: 0) {
                    mapSection
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .onAppear { locator.requestOneShotIfAuthorized() }
            .fullScreenCover(isPresented: $isWalking) { WalkTrackingView() }
            .sheet(isPresented: $showMonthlyDetail) {
                MonthlyDetailView(month: displayMonth, routes: routesIn(displayMonth))
            }
            .sheet(isPresented: $showMonthlyGallery) {
                MonthlyReviewGalleryView(routes: routes)
            }
        }
    }

    // MARK: - 统计卡（左右并排，等高，以右为准；右卡内容更高时左卡自动撑齐）

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { showMonthlyGallery = true } label: {
                MileageCard(month: displayMonth, routes: routesIn(displayMonth))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .buttonStyle(.plain)
            .measureStatCardHeight()

            MonthlyReviewCard(month: displayMonth, routes: routesIn(displayMonth)) {
                showMonthlyDetail = true
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .measureStatCardHeight()
        }
        .frame(height: maxStatCardHeight > 0 ? maxStatCardHeight : nil, alignment: .top)
        .onPreferenceChange(StatCardHeightKey.self) { newValue in
            // 只在变大时更新，避免因为拉高再触发测量而抖来抖去。
            if newValue > maxStatCardHeight { maxStatCardHeight = newValue }
        }
    }

    // MARK: - 上：地图 + 玻璃总览条 + 开遛按钮

    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            // 已授权才摆狗头；没授权就是一张普通地图，绝不为了展示 tab 去申请权限。
            PanoraMapView(
                pin: locator.lastKnownCoordinate,
                center: locator.lastKnownCoordinate,
                zoom: 15,
                interactive: true,
                pinWidth: 40
            )

            VStack {
                overviewGlassBar
                Spacer()
                Button { isWalking = true } label: {
                    Text("开遛！")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Panora.lime, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(Panora.ink)
                        .shadow(color: Panora.lime.opacity(0.35), radius: 12, y: 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .padding(.top, 12)
        }
        // 高度必须钉在 ZStack 上，不能只钉在地图上：叠在上面那层 VStack 里有个 Spacer，
        // 会把 ZStack 撑到 safeAreaInset 给的整屏高度，地图下面就多出一大片黑。
        .frame(height: 330)
    }

    private var overviewGlassBar: some View {
        HStack(spacing: 0) {
            overviewItem(String(format: "%.1f", totalKilometers), "总里程 (公里)")
            Rectangle().fill(Panora.dividerOnGlass).frame(width: 0.5, height: 30)
            overviewItem(totalDurationText, "总时长")
            Rectangle().fill(Panora.dividerOnGlass).frame(width: 0.5, height: 30)
            overviewItem("\(routes.count)", "遛狗次数")
        }
        .frame(height: 50)
        .panoraGlass(cornerRadius: 16)
        .padding(.horizontal, 16)
    }

    private func overviewItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentSectionHeader: some View {
        Text("最近遛狗")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Panora.textMuted)
    }

    private func recordRow(_ route: WalkRoute) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Panora.textPrimary)
                Text(String(format: "%.2f 公里 · %@", route.distanceMeters / 1000, durationText(route.durationSeconds)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Panora.textSecondary)
            }
            Spacer()
            if route.isKnownRoute {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Panora.greenOK)
                    .font(.system(size: 14))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .panoraCard(cornerRadius: 14)
    }

    // MARK: - 统计计算

    private var totalKilometers: Double { routes.reduce(0) { $0 + $1.distanceMeters } / 1000 }
    private var totalDurationText: String {
        let total = routes.reduce(0) { $0 + $1.durationSeconds }
        return String(format: "%.1f 时", Double(total) / 3600)
    }

    /// 统计卡显示哪个月：优先最近「有数据」的那个月；一条记录都没有时回落到当月。
    private var displayMonth: DateComponents {
        let latest = routes.first?.startDate ?? .now
        return Calendar.current.dateComponents([.year, .month], from: latest)
    }

    private func routesIn(_ month: DateComponents) -> [WalkRoute] {
        routes.filter {
            let c = Calendar.current.dateComponents([.year, .month], from: $0.startDate)
            return c.year == month.year && c.month == month.month
        }
    }

    private func deleteRecent(_ offsets: IndexSet) {
        let recent = Array(routes.prefix(10))
        for i in offsets where i < recent.count { context.delete(recent[i]) }
        try? context.save()
    }

    private func durationText(_ seconds: Int) -> String {
        let m = seconds / 60
        return "\(m) 分"
    }
}

/// 里程柱状卡：年月 + 当月公里 + 每日柱状图（1…月末）。深色卡。
private struct MileageCard: View {
    let month: DateComponents
    let routes: [WalkRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(monthTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Panora.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", monthKm))
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Panora.coral)
                Text("km")
                    .font(.system(size: 12))
                    .foregroundStyle(Panora.textSecondary)
            }
            .padding(.top, 2)
            barChart
                .padding(.top, 12)
            HStack {
                Text("1")
                Spacer()
                Text("\(daysInMonth)")
            }
            .font(.system(size: 9))
            .foregroundStyle(Panora.textMuted)
            .padding(.top, 5)
        }
        .padding(14)
        // maxHeight 必须撑在 .panoraCard() 之前：卡片背景是贴在这一层上的，
        // 只在外面拉高布局框的话背景还是自然高度，两张卡就对不齐。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .panoraCard()
    }

    private var barChart: some View {
        GeometryReader { geo in
            let height: CGFloat = geo.size.height
            let maxKm: Double = max(dailyKm.max() ?? 1, 0.1)
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    let km: Double = dailyKm[day - 1]
                    let ratio: CGFloat = CGFloat(km / maxKm)
                    let barHeight: CGFloat = max(CGFloat(2), height * ratio)
                    UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1)
                        .fill(km > 0 ? Panora.coral : Color.white.opacity(0.10))
                        .frame(height: barHeight)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 52)
    }

    private var monthTitle: String {
        String(format: "%d-%02d", month.year ?? 0, month.month ?? 0)
    }
    private var daysInMonth: Int {
        let cal = Calendar.current
        let date = cal.date(from: month) ?? .now
        return cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }
    private var monthKm: Double { routes.reduce(0) { $0 + $1.distanceMeters } / 1000 }
    private var dailyKm: [Double] {
        var arr = Array(repeating: 0.0, count: daysInMonth)
        for r in routes {
            let day = Calendar.current.component(.day, from: r.startDate)
            if day >= 1 && day <= daysInMonth { arr[day - 1] += r.distanceMeters / 1000 }
        }
        return arr
    }
}

/// 月度回顾卡：绿色月历（遛过的日子点亮）+ 当月遛狗次数；点开月度详情。深色卡。
private struct MonthlyReviewCard: View {
    let month: DateComponents
    let routes: [WalkRoute]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(month.month ?? 0)月回顾")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Panora.textPrimary)
                    Spacer()
                    Text("\(routes.count) 次 ›")
                        .font(.system(size: 11))
                        .foregroundStyle(Panora.textSecondary)
                }
                CalendarGrid(month: month, walkedDays: walkedDays, cellSpacing: 3, cornerRadius: 3)
            }
            .padding(14)
            // 同上：撑高要在贴卡片背景之前。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .panoraCard()
        }
        .buttonStyle(.plain)
    }

    private var walkedDays: Set<Int> {
        Set(routes.map { Calendar.current.component(.day, from: $0.startDate) })
    }
}

/// 月历格子：遛过的日子填绿。空格用 white 10%。
struct CalendarGrid: View {
    let month: DateComponents
    let walkedDays: Set<Int>
    var cellSpacing: CGFloat = 4
    var cornerRadius: CGFloat = 5

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7), spacing: cellSpacing) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
            ForEach(1...daysInMonth, id: \.self) { day in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(walkedDays.contains(day) ? Panora.greenOK : Color.white.opacity(0.10))
                    .aspectRatio(1, contentMode: .fit)
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

/// 月度回顾详情页（PRD §5.3）：主指标 里程 / 次数 / 时长 + 大月历。Panora 深色。
struct MonthlyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let month: DateComponents
    let routes: [WalkRoute]

    var body: some View {
        NavigationStack {
            ZStack {
                Panora.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(spacing: 0) {
                            metric(String(format: "%.1f", km), "公里", "总里程")
                            metric("\(routes.count)", "次", "遛狗次数")
                            metric(hoursText, "时", "总时长")
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 16)

                        CalendarGrid(month: month, walkedDays: walkedDays)
                            .padding(16)
                            .panoraCard()
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(String(format: "%d年 %d月回顾", month.year ?? 0, month.month ?? 0))
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func metric(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
                .contentTransition(.numericText(value: Double(value) ?? 0))
                .animation(.easeOut(duration: 0.6), value: value)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(Panora.textSecondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Panora.textMuted)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var km: Double { routes.reduce(0) { $0 + $1.distanceMeters } / 1000 }
    private var hoursText: String { String(format: "%.1f", Double(routes.reduce(0) { $0 + $1.durationSeconds }) / 3600) }
    private var walkedDays: Set<Int> { Set(routes.map { Calendar.current.component(.day, from: $0.startDate) }) }
}


// MARK: - 卡片等高（PreferenceKey 让 statsRow 里两张卡取最高的那张为准）

private struct StatCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func measureStatCardHeight() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: StatCardHeightKey.self, value: geo.size.height)
            }
        )
    }
}
