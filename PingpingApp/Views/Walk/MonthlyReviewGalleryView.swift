import SwiftUI
import UIKit

/// 遛狗回顾（月卡）—— Batch 1 §⑤：
/// 按月聚合 WalkRoute，竖排全幅照片月卡。入口 = 遛狗页里程柱状卡整卡点击。
/// 底部悬浮玻璃 Tab（原型有）暂不实现，因为要动全局 RootTabView；留给后面的 Batch。
struct MonthlyReviewGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let routes: [WalkRoute]

    @State private var selectedYear: Int
    /// 点月卡进 [[MonthPhotoCalendarView]] 用的 push target。
    /// DateComponents 不是 Identifiable，包一层 struct 才能喂给 navigationDestination(item:)。
    @State private var selectedMonth: MonthTarget?

    private struct MonthTarget: Hashable, Identifiable {
        let year: Int
        let month: Int
        var id: Int { year * 100 + month }
        var components: DateComponents { DateComponents(year: year, month: month) }
    }

    init(routes: [WalkRoute]) {
        self.routes = routes
        let years = Set(routes.map { Calendar.current.component(.year, from: $0.startDate) })
        _selectedYear = State(initialValue: years.max() ?? Calendar.current.component(.year, from: .now))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Panora.appBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 14) {
                        yearHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                        if monthsForYear.isEmpty {
                            emptyState
                        } else {
                            ForEach(monthsForYear, id: \.self) { month in
                                Button {
                                    selectedMonth = MonthTarget(
                                        year: month.year ?? selectedYear,
                                        month: month.month ?? 1
                                    )
                                } label: {
                                    MonthPhotoCard(
                                        month: month,
                                        routes: routesIn(month)
                                    )
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollContentBackground(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Panora.textPrimary)
                }
            }
            .navigationDestination(item: $selectedMonth) { target in
                MonthPhotoCalendarView(
                    month: target.components,
                    routes: routesIn(target.components)
                )
            }
            // 画廊现在也是常驻观赏面（月卡本身要展示贴纸），必须自己触发补跑，
            // 别指望用户会继续下钻到日历页才补 —— 那样画廊永远看不到东西。
            // 判断「需要跑」= 打分版本落后 OR 还没抠出图；这样升级 Scorer（比如加猫）时
            // 自动重扫老 route。
            .onAppear {
                let pending: [PhotoCutoutPipeline.PendingRoute] = routes
                    .filter { !$0.photosData.isEmpty
                        && PhotoCutoutPipeline.needsWork(
                            scorerVersion: $0.photoScorerVersion,
                            hasCutout: $0.cutoutData != nil
                        )
                    }
                    .map { .init(
                        id: $0.id,
                        photos: $0.photosData,
                        oldBestIndex: $0.bestPhotoIndex,
                        hasCutout: $0.cutoutData != nil
                    ) }
                PhotoCutoutPipeline.backfill(
                    pendingRoutes: pending,
                    container: context.container
                )
            }
        }
    }

    private var yearHeader: some View {
        HStack {
            Menu {
                ForEach(availableYears, id: \.self) { y in
                    Button("\(String(format: "%d", y)) 年") { selectedYear = y }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(format: "%d", selectedYear))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Panora.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Panora.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 18))
                .foregroundStyle(Panora.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(Panora.textMuted)
            Text("这一年还没有遛狗记录")
                .font(.system(size: 13))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 聚合

    private var availableYears: [Int] {
        let years = Set(routes.map { Calendar.current.component(.year, from: $0.startDate) })
        return years.sorted(by: >)
    }

    /// 该年出现过记录的月份，按新→旧。
    private var monthsForYear: [DateComponents] {
        var seen = Set<Int>()
        var result: [DateComponents] = []
        for r in routes {
            let c = Calendar.current.dateComponents([.year, .month], from: r.startDate)
            guard c.year == selectedYear, let m = c.month, !seen.contains(m) else { continue }
            seen.insert(m)
            result.append(c)
        }
        return result
    }

    private func routesIn(_ month: DateComponents) -> [WalkRoute] {
        routes.filter {
            let c = Calendar.current.dateComponents([.year, .month], from: $0.startDate)
            return c.year == month.year && c.month == month.month
        }
    }
}

/// 一张月卡：底图 = Panora 深色卡；上面挂 [[PhysicsCutoutScene]]，把当月已抠好的
/// 贴纸从顶上「倒进来」，真物理散落 + 堆到底边。月份数字放最底层做水印，
/// 玻璃药丸 (次数 · km) 悬在左上角，永远压在贴纸上面读得清。
private struct MonthPhotoCard: View {
    let month: DateComponents
    let routes: [WalkRoute]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 底：深色卡背景。贴纸落下去要有暗底衬托白描边。
            Panora.darkCard
            // 水印月份数字：压在最底层，贴纸落上去会遮住一部分 —— 就是要有物件堆在数字上的感觉。
            monthNumeral
            // 物理散落层：seed 用 year*100+month，同一张月卡每次进来落位一致，不会晃眼。
            PhysicsCutoutScene(
                cutouts: cutouts,
                seed: (month.year ?? 0) * 100 + (month.month ?? 0)
            )
            .allowsHitTesting(false)
            // 药丸永远在最上层，别被贴纸堆盖住。
            statPill
                .padding(14)
        }
        .frame(height: 218)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
        )
    }

    private var monthNumeral: some View {
        VStack {
            Spacer()
            HStack {
                Text(String(format: "%d月", month.month ?? 0))
                    .font(.system(size: 78, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35)) // 水印级淡度，让贴纸主角化
                    .padding(.leading, 18)
                    .padding(.bottom, 4)
                Spacer()
            }
        }
    }

    private var statPill: some View {
        HStack(spacing: 8) {
            Text("\(routes.count) 次")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            Text("·")
                .foregroundStyle(Panora.textSecondary)
            Text(String(format: "%.0fkm", km))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Panora.textPrimary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .panoraGlass(cornerRadius: 999)
    }

    private var km: Double { routes.reduce(0) { $0 + $1.distanceMeters } / 1000 }

    /// 当月已抠好的贴纸，按 route 时间从旧到新排。物理里落进来的顺序 = 数组顺序。
    /// 没抠好的 route（cutoutData == nil）跳过。补跑陆续到齐时，updateUIView 会追加新的进物理。
    private var cutouts: [UIImage] {
        routes
            .sorted { $0.startDate < $1.startDate }
            .compactMap { $0.cutoutData }
            .compactMap { UIImage(data: $0) }
    }
}
