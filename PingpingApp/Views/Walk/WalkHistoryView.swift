import SwiftUI
import SwiftData
import MapKit

/// 遛狗 Tab（PRD §5.3）：「开遛 + 统计」合成一页。
/// 上：地图（狗站在定位）+ 总览 + 扁长「开遛！」按钮叠在地图上；
/// 下：里程柱状卡（最近有数据的月）+ 月度回顾卡（点开详情）+ 最近记录（可删）。
struct WalkHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WalkRoute.startDate, order: .reverse) private var routes: [WalkRoute]
    @State private var isWalking = false
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showMonthlyDetail = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    mapSection
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                // 统计卡常驻：没记录时也照常显示，只是里程 0、柱子和月历全灰。
                Section {
                    MileageCard(month: displayMonth, routes: routesIn(displayMonth))
                    MonthlyReviewCard(month: displayMonth, routes: routesIn(displayMonth)) { showMonthlyDetail = true }
                }
                .listRowSeparator(.hidden)
                Section("最近遛狗") {
                    if routes.isEmpty {
                        Text("还没有记录，点地图上的「开遛！」开始第一次遛狗")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(routes.prefix(10).map { $0 }) { route in
                            recordRow(route)
                        }
                        .onDelete(perform: deleteRecent)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("遛狗")
            .fullScreenCover(isPresented: $isWalking) { WalkTrackingView() }
            .sheet(isPresented: $showMonthlyDetail) {
                MonthlyDetailView(month: displayMonth, routes: routesIn(displayMonth))
            }
        }
    }

    // MARK: - 上：地图 + 总览 + 开遛按钮

    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) { UserAnnotation() }
                .mapControlVisibility(.hidden)
                .frame(height: 300)

            VStack {
                overviewBar
                Spacer()
                Button { isWalking = true } label: {
                    Text("开遛！")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(AppTheme.lime, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(AppTheme.ink)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .padding(.top, 12)
        }
    }

    private var overviewBar: some View {
        HStack(spacing: 0) {
            overviewItem(String(format: "%.1f", totalKilometers), "总里程 (公里)")
            Divider().frame(height: 30)
            overviewItem(totalDurationText, "总时长")
            Divider().frame(height: 30)
            overviewItem("\(routes.count)", "遛狗次数")
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func overviewItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func recordRow(_ route: WalkRoute) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.startDate.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                Text(String(format: "%.2f 公里 · %@", route.distanceMeters / 1000, durationText(route.durationSeconds)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if route.isKnownRoute {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.greenOK).font(.caption)
            }
        }
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

/// 里程柱状卡：年月 + 当月公里 + 每日柱状图（1…月末）。
private struct MileageCard: View {
    let month: DateComponents
    let routes: [WalkRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(monthTitle).font(.headline)
                Text(String(format: "%.1f 公里", monthKm)).font(.title3.bold()).foregroundStyle(AppTheme.coral)
                Spacer()
            }
            barChart
            HStack { Text("1").font(.caption2); Spacer(); Text("\(daysInMonth)").font(.caption2) }
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(AppTheme.stageGray, in: RoundedRectangle(cornerRadius: 16))
    }

    private var barChart: some View {
        GeometryReader { geo in
            let maxKm = max(dailyKm.max() ?? 1, 0.1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...daysInMonth, id: \.self) { day in
                    let km = dailyKm[day - 1]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(km > 0 ? AppTheme.coral : Color.secondary.opacity(0.15))
                        .frame(height: max(2, geo.size.height * km / maxKm))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 60)
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

/// 月度回顾卡：绿色月历（遛过的日子点亮）+ 当月遛狗次数；点开月度详情。
private struct MonthlyReviewCard: View {
    let month: DateComponents
    let routes: [WalkRoute]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(month.month ?? 0)月回顾").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text("\(routes.count) 次 ›").font(.subheadline).foregroundStyle(.secondary)
                }
                CalendarGrid(month: month, walkedDays: walkedDays)
            }
            .padding(16)
            .background(AppTheme.stageGray, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var walkedDays: Set<Int> {
        Set(routes.map { Calendar.current.component(.day, from: $0.startDate) })
    }
}

/// 月历格子：遛过的日子填绿。
private struct CalendarGrid: View {
    let month: DateComponents
    let walkedDays: Set<Int>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 22) }
            ForEach(1...daysInMonth, id: \.self) { day in
                RoundedRectangle(cornerRadius: 5)
                    .fill(walkedDays.contains(day) ? AppTheme.greenOK : Color.secondary.opacity(0.12))
                    .frame(height: 22)
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

/// 月度回顾详情页（PRD §5.3）：主指标 里程 / 次数 / 时长（已去掉配速、消耗）+ 月历。
struct MonthlyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let month: DateComponents
    let routes: [WalkRoute]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 0) {
                        metric(String(format: "%.1f", km), "公里", "总里程")
                        metric("\(routes.count)", "次", "遛狗次数")
                        metric(hoursText, "时", "总时长")
                    }
                    .padding(.top, 8)

                    CalendarGrid(month: month, walkedDays: walkedDays)
                        .padding(16)
                        .background(AppTheme.stageGray, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
            }
            .navigationTitle(String(format: "%d年 %d月回顾", month.year ?? 0, month.month ?? 0))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func metric(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 34, weight: .bold)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.secondary)
            Text(label).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var km: Double { routes.reduce(0) { $0 + $1.distanceMeters } / 1000 }
    private var hoursText: String { String(format: "%.1f", Double(routes.reduce(0) { $0 + $1.durationSeconds }) / 3600) }
    private var walkedDays: Set<Int> { Set(routes.map { Calendar.current.component(.day, from: $0.startDate) }) }
}
