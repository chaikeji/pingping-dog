import SwiftUI
import SwiftData

/// 月度照片日历：从 [[MonthlyReviewGalleryView]] 的月卡点进来。7 列日历格，有照片的
/// 那天贴当天「照片最多那次」的第一张，多张时右上角挂一个数量小徽章；没照片的那天露灰底日期。
///
/// 下面两张卡：本月摘要（公里 / 次 / 遇见的狗朋友数）+ 常遇见的狗朋友头像叠一层。
///
/// 抠图 API 接上后：把 photoImage 换成透明贴纸 + 「从天上掉进日期格」的 spring 动画；
/// 现在先用原图 + 圆角占位把结构立起来，先跑通视觉，再上贴纸。
struct MonthPhotoCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let month: DateComponents
    let routes: [WalkRoute]

    /// 头像用 —— 按 ID 反查，@Query 拉一次全表比每次去主库好。
    @Query private var allFriends: [DogFriend]

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                        .padding(.top, 4)

                    weekdayRow
                        .padding(.horizontal, 16)

                    calendarGrid
                        .padding(.horizontal, 16)

                    summaryBar
                        .padding(.horizontal, 16)

                    if !topFriends.isEmpty {
                        friendsCard
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Panora.textPrimary)
                }
            }
        }
        // 补跑：老 route 从没进过链路，或者 Scorer 升过版（比如加了猫识别），进来时补一遍。
        // 已经跟当前版本对齐、且已经有 cutout 的 route 会被 needsWork 判掉，进出不会二次刷。
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("\(month.month ?? 0) 月")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Panora.textPrimary)
            Text(String(format: "%d 年", month.year ?? 0))
                .font(.system(size: 13))
                .foregroundStyle(Panora.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Weekday row

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Panora.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        // 全月分配算一次就够 —— 借用池要一次性分完才知道哪张贴纸给了谁。
        // 分完的 map 传给每个 dayCell，避免 31 次重复算。
        let assignments = dayAssignments
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
            spacing: 6
        ) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day: day, entry: assignments[day] ?? DayEntry.empty)
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int, entry: DayEntry) -> some View {
        // 拆两层：底层是常规格子内容（灰底 + 照片 / 日期数字），走 clipShape 保圆角；
        // 顶层是贴纸下落层，**不 clip**，能从 -200pt 上空落进格子，途经上一行的格子也允许。
        // 落地后 zIndex 收回 0，回到普通渲染层级。
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // 底层：非贴纸内容 + clip
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))

                    if entry.sticker == nil, let photo = entry.fallbackPhoto {
                        // 没抠好时退回原图缩略
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else if entry.sticker == nil {
                        // 都没有 → 日期数字
                        Text("\(day)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Panora.textMuted)
                            .monospacedDigit()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    // 照片型格子加一层描边，跟贴纸型的烘白描边视觉呼应。
                    if entry.sticker == nil && entry.fallbackPhoto != nil {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    }
                }
            }
            .overlay {
                // 贴纸层：不裁，允许从格子上方 200pt 高处掉进来，途中盖过隔壁格子。
                if let sticker = entry.sticker {
                    StickerDropView(image: sticker, day: day)
                        .padding(2)
                }
            }
            .overlay(alignment: .topTrailing) { countBadge(entry.count) }
    }

    @ViewBuilder
    private func countBadge(_ count: Int) -> some View {
        if count > 1 {
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(badgeColor))
                .offset(x: 4, y: -4)
        }
    }

    /// 参考图里那个米黄计数徽章的色。定死一个 hex，不走主题 —— 它必须在照片上和灰底上都读得清。
    private var badgeColor: Color { Color(hex: 0xE8C486) }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            summaryItem(String(format: "%.1f", monthKm), "公里")
            Rectangle().fill(Panora.dividerOnGlass).frame(width: 0.5, height: 30)
            summaryItem("\(routes.count)", "次")
            Rectangle().fill(Panora.dividerOnGlass).frame(width: 0.5, height: 30)
            summaryItem("\(uniqueFriendIDs.count)", "位狗朋友")
        }
        .frame(height: 60)
        .panoraGlass(cornerRadius: 16)
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Panora.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Friends card

    private var friendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("常遇见的狗朋友")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Panora.textPrimary)
                Spacer()
                Text("\(topFriends.count) 位")
                    .font(.system(size: 12))
                    .foregroundStyle(Panora.textSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: -10) {
                ForEach(Array(topFriends.prefix(5).enumerated()), id: \.element.id) { idx, f in
                    friendAvatar(f)
                        .zIndex(Double(-idx))
                }
                if topFriends.count > 5 {
                    Text("+\(topFriends.count - 5)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Panora.textPrimary)
                        .monospacedDigit()
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().stroke(Panora.ink, lineWidth: 2))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panoraCard()
    }

    private func friendAvatar(_ f: DogFriend) -> some View {
        Group {
            if let data = f.avatarData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.white.opacity(0.15))
                    Text(String(f.name.prefix(1)))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Panora.textPrimary)
                }
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay(Circle().stroke(Panora.ink, lineWidth: 2))
    }

    // MARK: - Data helpers

    private struct DayEntry {
        /// 首选贴纸：自家抠的 或 从其它天借来的（每张贴纸整月只用一次）。
        let sticker: UIImage?
        /// 没贴纸也没借到时的退化：当天照片最多那次的第一张原图。
        let fallbackPhoto: UIImage?
        /// 当天所有 route 的照片张数之和 —— 徽章用它，不是 route 数。
        let count: Int
        /// 借用来的贴纸标记，UI 目前不区分（用户想让它无缝），保留字段方便以后加视觉暗示。
        let borrowed: Bool

        static let empty = DayEntry(sticker: nil, fallbackPhoto: nil, count: 0, borrowed: false)
    }

    /// 全月一次分配：每张 cutout 整月只用一次；自家 day 优先，多余的塞给「有照片但没自家 cutout」的 day。
    /// 规则：
    /// 1. 每个 day 挑自家 photoScore 最高的 cutout 当首选；剩下的 cutout 进 leftover 池
    /// 2. 「有照片但没自家 cutout」的 day 按日期升序，从 leftover 池头部借（池按分数倒序）
    /// 3. 池空了 → 后备原图缩略图 4. 一张照片都没 → 露日期数字
    private var dayAssignments: [Int: DayEntry] {
        let cal = Calendar.current

        // ── Step 1: 按天分桶
        struct Bucket {
            var routes: [WalkRoute] = []
            var cutouts: [(route: WalkRoute, score: Double)] = []
        }
        var buckets: [Int: Bucket] = [:]
        for r in routes {
            let day = cal.component(.day, from: r.startDate)
            var b = buckets[day, default: Bucket()]
            b.routes.append(r)
            if r.cutoutData != nil {
                let score = r.photoScores.max() ?? 0
                b.cutouts.append((r, score))
            }
            buckets[day] = b
        }

        // ── Step 2: 自家优先，多余入池
        var result: [Int: DayEntry] = [:]
        var leftovers: [(image: UIImage, score: Double)] = []

        for (day, bucket) in buckets {
            let totalPhotos = bucket.routes.reduce(0) { $0 + $1.photosData.count }
            let sortedCuts = bucket.cutouts.sorted { $0.score > $1.score }

            if let best = sortedCuts.first,
               let img = best.route.cutoutData.flatMap({ UIImage(data: $0) }) {
                result[day] = DayEntry(sticker: img, fallbackPhoto: nil, count: totalPhotos, borrowed: false)
                for extra in sortedCuts.dropFirst() {
                    if let extraImg = extra.route.cutoutData.flatMap({ UIImage(data: $0) }) {
                        leftovers.append((extraImg, extra.score))
                    }
                }
            } else {
                // 没自家 cutout：记后备原图，等第 3 步看能不能借到贴纸
                let fbWalk = bucket.routes.max(by: { $0.photosData.count < $1.photosData.count })
                let fbImg = fbWalk?.photosData.first.flatMap { UIImage(data: $0) }
                result[day] = DayEntry(sticker: nil, fallbackPhoto: fbImg, count: totalPhotos, borrowed: false)
            }
        }

        // ── Step 3: 借用池按分数倒序，塞给「有照片但没自家 cutout」的 day（日期升序）
        var pool = leftovers.sorted { $0.score > $1.score }
        for day in result.keys.sorted() {
            let entry = result[day]!
            guard entry.sticker == nil, entry.fallbackPhoto != nil, !pool.isEmpty else { continue }
            let borrowed = pool.removeFirst()
            result[day] = DayEntry(
                sticker: borrowed.image,
                fallbackPhoto: entry.fallbackPhoto, // 保留 fallback，万一以后想切换回原图
                count: entry.count,
                borrowed: true
            )
        }

        return result
    }

    private var monthKm: Double { routes.reduce(0) { $0 + $1.distanceMeters } / 1000 }

    private var uniqueFriendIDs: Set<UUID> {
        Set(routes.flatMap { $0.metDogFriendIDs })
    }

    /// 本月遇见过的狗朋友，按「本月相遇次数」倒序。同次数保持稳定顺序（按 UUID）。
    private var topFriends: [DogFriend] {
        var counts: [UUID: Int] = [:]
        for r in routes {
            for id in r.metDogFriendIDs { counts[id, default: 0] += 1 }
        }
        let orderedIDs = counts.keys.sorted {
            let a = counts[$0, default: 0]
            let b = counts[$1, default: 0]
            return a != b ? a > b : $0.uuidString < $1.uuidString
        }
        return orderedIDs.compactMap { id in allFriends.first { $0.id == id } }
    }

    private var daysInMonth: Int {
        let cal = Calendar.current
        let date = cal.date(from: month) ?? .now
        return cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// 当月 1 号落在第几列（周一为第 0 列，跟 [[WalkHistoryView]] 里的 CalendarGrid 对齐）。
    private var leadingBlanks: Int {
        let cal = Calendar.current
        guard let first = cal.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else { return 0 }
        let weekday = cal.component(.weekday, from: first) // 周日=1
        return (weekday + 5) % 7
    }
}

/// 一颗贴纸的「从天上掉进日期格」动画：初次上屏时 spring 落下，带一点点稳定的斜角 + 阴影落地。
/// 描边已经在 [[CutoutCleaner]] 里烘进 PNG 里了，这里只管形变和阴影。
/// 每一天的贴纸「从格子上方 200pt 高处以重力感掉进来」的入场动画。
///
/// - 起点：`y = -200`（格子正上方 200pt，视觉上看得见完整下落）；父视图**不 clip 贴纸层**，
///   下落路径会盖过隔壁格子 —— 用 `zIndex(999)` 在动画期间抬到最上层。
/// - 曲线：低阻尼 spring，让落地那一下有真实弹跳感（不是匀速掉下去然后一下停住）。
/// - 旋转：初始角度 = 最终落定角度 × -2.5，掉的过程有甩正的力矩感。
/// - 落地后：`zIndex` 收回 0，回到普通层级。
private struct StickerDropView: View {
    let image: UIImage
    let day: Int
    @State private var landed = false

    /// 贴纸起始高度（相对目标位置向上偏移）。200pt 差不多是 3 行日历格的高度。
    private let dropHeight: CGFloat = 200

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .rotationEffect(.degrees(landed ? finalTilt : dropTilt))
            .offset(y: landed ? 0 : -dropHeight)
            .shadow(color: .black.opacity(landed ? 0.28 : 0.12), radius: landed ? 2 : 4, y: landed ? 1.5 : 3)
            // 下落中永远最上层，途经隔壁格子不会被裁；落定后收回，跟别的贴纸正常层级。
            .zIndex(landed ? 0 : 999)
            .onAppear {
                // 按天错开：整月一起哗啦啦下来比同帧砸下更有物件感。
                // % 12 让隔了 12 天的两张贴纸同时掉 —— 均匀铺满 ~0.7s 一个周期。
                let delay = Double(day % 12) * 0.06
                // 低阻尼 spring：response 0.85 给足下落时间看得清，damping 0.55 落地弹两下。
                withAnimation(.spring(response: 0.85, dampingFraction: 0.55).delay(delay)) {
                    landed = true
                }
            }
    }

    /// 落地后的最终微斜：按日期取值，每天固定 —— 不会因为 view 重建就晃到别的角度。
    private var finalTilt: Double {
        let choices = [-6.0, -2.0, 3.0, -4.0, 1.0, 5.0, -1.0]
        return choices[day % choices.count]
    }

    /// 空中初始角度：拉大一档，跟落地角度反向，掉进去会有个甩正的感觉。
    private var dropTilt: Double { -finalTilt * 2.5 }
}
