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
                                    PagePerformanceMonitor.shared.navigationBegan(
                                        to: "里程统计-单月月历",
                                        context: "month=\(month.year ?? 0)-\(month.month ?? 0), routes=\(routesIn(month).count)"
                                    )
                                    selectedMonth = MonthTarget(
                                        year: month.year ?? selectedYear,
                                        month: month.month ?? 1
                                    )
                                } label: {
                                    MonthPhotoCard(
                                        month: month,
                                        routes: routesIn(month),
                                        physicsEnabled: selectedMonth == nil
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
                PagePerformanceMonitor.shared.pageAppeared(
                    "里程统计-月份列表",
                    context: "routes=\(routes.count), months=\(monthsForYear.count)"
                )
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
                        oldExtraIndex: $0.extraCutoutPhotoIndex,
                        hasCutout: $0.cutoutData != nil,
                        hasExtraCutout: $0.extraCutoutData != nil
                    ) }
                PhotoCutoutPipeline.backfill(
                    pendingRoutes: pending,
                    container: context.container
                )
            }
            .task(id: calendarPrewarmID, priority: .utility) {
                // 第一层先完成自身绘制，再准备最近两个月的第二层素材；进入某个月后立即取消。
                guard selectedMonth == nil else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, selectedMonth == nil else { return }
                let requests = MileageImagePrewarmer.calendarRequests(routes: routes)
                await MileageImagePrewarmer.prewarm(requests, batchSize: 3)
            }
        }
    }

    private var calendarPrewarmID: String {
        let contentID = routes.map {
            "\($0.id)-v\($0.photoScorerVersion ?? 0)"
                + "-c\($0.cutoutData?.count ?? 0)-e\($0.extraCutoutData?.count ?? 0)"
                + "-f\($0.photosData.first?.count ?? 0)"
        }.joined(separator: ",")
        return "selected=\(selectedMonth?.id ?? 0)-\(contentID)"
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
/// 贴纸从卡顶更高处（+180pt 上溢出区）掉下来，真物理散落 + 堆到底边。
/// 月份数字压在最底层做水印，玻璃药丸悬在左上角始终读得清。
///
/// 关键结构：卡片本体（深色底 + 数字 + 药丸）走独立 clipShape 保住圆角；
/// 物理层套在 ZStack 里但**不裁**，能溢出到卡顶上方 180pt，让贴纸的下落过程真的看得见。
/// 在 LazyVStack 里会短暂盖住上一张卡 —— 值，换来了"从天上掉下来"的感觉。
private struct MonthPhotoCard: View {
    let month: DateComponents
    let routes: [WalkRoute]
    let physicsEnabled: Bool

    /// 卡片本体高度（视觉上的卡片）。
    private let cardHeight: CGFloat = 218
    /// 物理层向上延伸多少 pt。这段区域视觉可见，就是"贴纸从卡顶更高处掉下来"的那段路径。
    private let spawnZoneAboveCard: CGFloat = 180

    /// 从 [[CutoutImageCache]] 异步加载好的、已 preparingForDisplay 解码的 UIImage 数组。
    /// 之所以不再走计算属性：`UIImage(data:)` 每次 body 都重建实例，位图解码堵在物理动画头几帧，
    /// 就是掉落卡顿的元凶。这里加载一次、缓存复用，第二次进画廊直接命中缓存。
    @State private var decodedCutouts: [UIImage] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            // 卡片本体：单独 clipShape，圆角保住。贴纸不裁进这里。
            ZStack(alignment: .topLeading) {
                Panora.darkCard
                statPill.padding(14)
            }
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
            )

            // 物理层：更高（cardHeight + spawnZone），底对齐到卡底 → 顶部溢出到卡上方。
            // 不 clip，贴纸下落过程整段可见。alignment=.bottom 让底对齐生效。
            PhysicsCutoutScene(
                cutouts: decodedCutouts,
                seed: (month.year ?? 0) * 100 + (month.month ?? 0),
                cardHeight: cardHeight,
                spawnAboveHeight: spawnZoneAboveCard,
                isActive: physicsEnabled
            )
            .frame(height: cardHeight + spawnZoneAboveCard)
            .allowsHitTesting(false)
        }
        .frame(height: cardHeight) // 布局尺寸只算卡片本身；物理层溢出不占空间
        // task id 变化 = 需要重跑加载：补跑写入新 cutout 会跳版本 → id 里的 -v段变 → 重跑。
        // routes 数量变化（新遛狗）也会让 id 变。稳态下 id 稳定，.task 不重复触发。
        .task(id: cutoutTaskID) {
            await loadCutouts()
        }
    }

    /// 药丸：N月 · 次数 · 公里数，三段同字号（12pt semibold）。
    /// 原来底下那颗 78pt 大水印月份被这里统一收编 —— 视觉主角完全交给物理贴纸。
    private var statPill: some View {
        HStack(spacing: 8) {
            Text("\(month.month ?? 0)月")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            Text("·")
                .foregroundStyle(Panora.textSecondary)
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

    /// `.task(id:)` 的 id：只统计有 cutout 的 route，把 id + 版本拼串。
    /// 补跑重抠会跳 photoScorerVersion → 串变 → task 重跑；否则稳定不重触发。
    private var cutoutTaskID: String {
        routes.compactMap { r in
            r.cutoutData != nil ? "\(r.id)-v\(r.photoScorerVersion ?? 0)" : nil
        }.joined(separator: ",")
    }

    /// 加载当月贴纸：按 route 时间从旧到新，逐个走 [[CutoutImageCache]] 拿解好的 UIImage。
    /// 缓存命中就是纯查表，几乎零耗时；未命中在后台线程解一次并缓存。
    /// 结果一次性 set 给 decodedCutouts → SwiftUI 触发一次 updateUIView → 物理层错峰入场。
    private func loadCutouts() async {
        // Let the sheet/navigation transition finish before adding decoded images to
        // multiple UIDynamicAnimator scenes on the main thread.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let loadStartedAt = ProcessInfo.processInfo.systemUptime
        let sorted = routes.sorted { $0.startDate < $1.startDate }
        var result: [UIImage] = []
        for route in sorted {
            guard let data = route.cutoutData else { continue }
            let key = "\(route.id)-v\(route.photoScorerVersion ?? 0)"
            if let img = await CutoutImageCache.shared.image(
                for: key,
                data: data,
                maxPixelSize: 256
            ) {
                result.append(img)
            }
        }
        guard !Task.isCancelled else { return }
        decodedCutouts = result
        PagePerformanceMonitor.shared.workFinished(
            page: "里程统计-月份列表",
            phase: "贴纸图片准备",
            startedAt: loadStartedAt,
            context: "month=\(month.year ?? 0)-\(month.month ?? 0), images=\(result.count)"
        )
    }
}
