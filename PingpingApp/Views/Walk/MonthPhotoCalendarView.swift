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
    let month: DateComponents
    let routes: [WalkRoute]

    /// 头像用 —— 按 ID 反查，@Query 拉一次全表比每次去主库好。
    @Query private var allFriends: [DogFriend]
    @State private var dayAssignments: [Int: DayEntry] = [:]
    @State private var stickersLanded = false

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()
            ScrollView {
                // 之前顶部有一颗 44pt 大月份 + 小年份，占三行位置。
                // 现在移到导航栏挨着返回键，日历直接顶上去、多露一整行日期格。
                VStack(spacing: 16) {
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
                .padding(.top, 4)
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
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("返回")
            }
            // 标题由系统放在导航栏中央，和左右按钮分别占位，窄屏也不会互相覆盖。
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(String(format: "%d 年", month.year ?? 0))
                        .font(.system(size: 11))
                        .foregroundStyle(Panora.textSecondary)
                        .monospacedDigit()
                    Text("\(month.month ?? 0) 月")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Panora.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .onAppear {
            PagePerformanceMonitor.shared.pageAppeared(
                "里程统计-单月月历",
                context: "month=\(month.year ?? 0)-\(month.month ?? 0), routes=\(routes.count)"
            )
        }
        .task(id: assignmentTaskID) {
            let startedAt = ProcessInfo.processInfo.systemUptime
            stickersLanded = false
            dayAssignments = await buildDayAssignments()
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeIn(duration: 0.48)) {
                stickersLanded = true
            }
            PagePerformanceMonitor.shared.workFinished(
                page: "里程统计-单月月历",
                phase: "整月数据和图片准备",
                startedAt: startedAt,
                context: "assignedDays=\(dayAssignments.count)"
            )
        }
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
        // 合成 42 格（6 行 × 7 列）的一维数组：nil = 空格，Int = 日期。
        // 用单个 ForEach 走完，id 是数组下标 → 全 grid 内 id 唯一。
        //
        // 之前拆两个 ForEach（一个走 blanks 一个走 days）都用 `\.self` 做 id，
        // blank id 0..<leadingBlanks 会跟 day id 1...leadingBlanks **撞车**（比如
        // 8 月 leadingBlanks=5，blank id 0-4 撞 day id 1-4），SwiftUI 把撞车的
        // 第二份当"更新"而不是"新增" → day 1..4 直接消失。这才是 8/1-8/4 在日历上
        // 不显示的真根因。绕过 RoundedRectangle / Color.clear 布局那一整套推测
        // 都是走远路，真凶就是 ForEach id 冲突。
        //
        // 顺便补 trailing blank 到 42，所有月份 grid 都是 6 行 —— 首页两颗小卡
        // 等高布局也不会因为月份不同一大一小。
        let cells: [Int?] = Array(repeating: nil as Int?, count: leadingBlanks)
            + (1...daysInMonth).map { Optional($0) }
            + Array(repeating: nil as Int?, count: max(0, 42 - leadingBlanks - daysInMonth))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
            spacing: 6
        ) {
            ForEach(cells.indices, id: \.self) { i in
                if let day = cells[i] {
                    dayCell(day: day, entry: assignments[day] ?? DayEntry.empty)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int, entry: DayEntry) -> some View {
        // 回到 clip 内叠贴纸的经典布局：所有内容都在圆角矩形里，无跨格溢出。
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))

                    if let sticker = entry.sticker {
                        StickerDropView(image: sticker, day: day, landed: stickersLanded)
                            .padding(2)
                    } else if let photo = entry.fallbackPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Text("\(day)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Panora.textMuted)
                            .monospacedDigit()
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if entry.sticker == nil && entry.fallbackPhoto != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
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

    /// 全月一次分配：每张 cutout 整月只用一次；只给"有 route 的 day"分贴纸，"没遛狗的 day"严格露日期数字。
    /// 规则：
    /// 1. 每个有 route 的 day 挑自家 photoScore 最高的 cutout 当首选；剩下 cutout 进 leftover 池
    /// 2. 每 route 的 extraCutoutData（次高分抠图）也进池
    /// 3. 「有 route 但没自家贴纸」的 day 按日期升序从池头借
    ///    —— 覆盖两种情况：有照片但抠图挂了 / 打分没过门槛；以及有 route 但没拍照
    /// 4. 没 route 的 day → 不填，dayCell 拿 DayEntry.empty 露灰底日期数字
    ///    （之前会用剩余池 + 原图池给纯空日凑一张贴纸，用户反馈这不对：没遛狗就应该看得出没遛狗）
    private var assignmentTaskID: String {
        routes.map { route in
            let fallbackBytes = route.photosData.first?.count ?? 0
            return "\(route.id)-v\(route.photoScorerVersion ?? 0)"
                + "-c\(route.cutoutData?.count ?? 0)"
                + "-e\(route.extraCutoutData?.count ?? 0)"
                + "-p\(route.photosData.count)-f\(fallbackBytes)"
        }.joined(separator: ",")
    }

    private func buildDayAssignments() async -> [Int: DayEntry] {
        let cal = Calendar.current

        // 第二层会用主贴纸、额外贴纸和备用原图。先去重，再分批并行解码；
        // 旧实现逐张 await，7 月图片多时必须排完整条队伍，日期先出现、贴纸晚一秒才一起出现。
        var imageRequests: [String: Data] = [:]
        for route in routes {
            let version = route.photoScorerVersion ?? 0
            if let data = route.cutoutData {
                imageRequests["\(route.id)-v\(version)"] = data
            }
            if let data = route.extraCutoutData {
                imageRequests["\(route.id)-extra-v\(version)"] = data
            }
        }
        // 每个有记录的日期最多只需要一张备用原图，不把同一天所有 route 的原图都解码。
        let routesByDay = Dictionary(grouping: routes) { cal.component(.day, from: $0.startDate) }
        for dayRoutes in routesByDay.values {
            guard let fallback = dayRoutes.max(by: { $0.photosData.count < $1.photosData.count }),
                  let data = fallback.photosData.first else { continue }
            imageRequests["\(fallback.id)-fallback-0"] = data
        }
        SessionEventLog.log(
            "perf.calendar.plan",
            context: "month=\(month.year ?? 0)-\(month.month ?? 0), routes=\(routes.count), main=\(routes.filter { $0.cutoutData != nil }.count), extra=\(routes.filter { $0.extraCutoutData != nil }.count), fallbackDays=\(routesByDay.count), uniqueRequests=\(imageRequests.count)"
        )
        let preparedImages = await loadImagesInParallel(imageRequests)

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

        // v4 起每 route 会额外抠一张次高分作为"额外贴纸"，全部丢进池给别的日子借。
        // 不区分是哪天贡献的 —— 池按分数倒序全月共享。
        for r in routes {
            let key = "\(r.id)-extra-v\(r.photoScorerVersion ?? 0)"
            if let img = preparedImages[key] {
                let s: Double
                if let idx = r.extraCutoutPhotoIndex, r.photoScores.indices.contains(idx) {
                    s = r.photoScores[idx]
                } else {
                    s = 0
                }
                leftovers.append((img, s))
            }
        }

        for (day, bucket) in buckets {
            let totalPhotos = bucket.routes.reduce(0) { $0 + $1.photosData.count }
            let sortedCuts = bucket.cutouts.sorted { $0.score > $1.score }

            if let best = sortedCuts.first,
               let img = preparedImages["\(best.route.id)-v\(best.route.photoScorerVersion ?? 0)"] {
                result[day] = DayEntry(sticker: img, fallbackPhoto: nil, count: totalPhotos, borrowed: false)
                for extra in sortedCuts.dropFirst() {
                    if let extraImg = preparedImages["\(extra.route.id)-v\(extra.route.photoScorerVersion ?? 0)"] {
                        leftovers.append((extraImg, extra.score))
                    }
                }
            } else {
                // 没自家 cutout：记后备原图，等第 3 步看能不能借到贴纸
                let fbWalk = bucket.routes.max(by: { $0.photosData.count < $1.photosData.count })
                let fbImg = fbWalk.flatMap { preparedImages["\($0.id)-fallback-0"] }
                result[day] = DayEntry(sticker: nil, fallbackPhoto: fbImg, count: totalPhotos, borrowed: false)
            }
        }

        // ── Step 3: 借用池按分数倒序，塞所有「有 route 但没自家贴纸」的 day
        // 之前这里还要求 fallbackPhoto != nil（等于要求"至少拍了一张照片"），
        // 现在放开：只要有 route + 没贴纸就借，覆盖"遛狗了但没拍照"的日子。
        // 没 route 的日子在这个循环之外，一律保持不填。
        var pool = leftovers.sorted { $0.score > $1.score }
        for day in result.keys.sorted() {
            let entry = result[day]!
            guard entry.sticker == nil, !pool.isEmpty else { continue }
            let borrowed = pool.removeFirst()
            result[day] = DayEntry(
                sticker: borrowed.image,
                fallbackPhoto: entry.fallbackPhoto,
                count: entry.count,
                borrowed: true
            )
        }

        let stickerCount = result.values.filter { $0.sticker != nil }.count
        let fallbackCount = result.values.filter { $0.sticker == nil && $0.fallbackPhoto != nil }.count
        SessionEventLog.log(
            "perf.calendar.result",
            context: "month=\(month.year ?? 0)-\(month.month ?? 0), prepared=\(preparedImages.count), assignedDays=\(result.count), stickers=\(stickerCount), fallbacks=\(fallbackCount)"
        )
        return result
    }

    /// 同时解码过多图片会反过来争抢 CPU；每批最多 6 张，在速度和首屏稳定性之间取平衡。
    private func loadImagesInParallel(_ requests: [String: Data]) async -> [String: UIImage] {
        let entries = Array(requests)
        var result: [String: UIImage] = [:]
        for start in stride(from: 0, to: entries.count, by: 6) {
            guard !Task.isCancelled else { return [:] }
            let batch = entries[start..<min(start + 6, entries.count)]
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for (key, data) in batch {
                    group.addTask {
                        let image = await CutoutImageCache.shared.image(
                            for: key,
                            data: data,
                            maxPixelSize: 256
                        )
                        return (key, image)
                    }
                }
                for await (key, image) in group {
                    if let image { result[key] = image }
                }
            }
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

/// 一颗贴纸的「从天上掉进日期格」动画：初次上屏时单向落下，带一点点稳定的斜角 + 阴影落地。
/// 描边已经在 [[CutoutCleaner]] 里烘进 PNG 里了，这里只管形变和阴影。
/// 每一天的贴纸从格子上方落入；贴纸层不裁切，因此下落路径真实可见。
private struct StickerDropView: View {
    let image: UIImage
    let day: Int
    let landed: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .rotationEffect(.degrees(landed ? finalTilt : dropTilt))
            .offset(y: landed ? 0 : -52)
            .scaleEffect(landed ? 1 : 0.94)
            .opacity(landed ? 1 : 0.18)
            .shadow(color: .black.opacity(landed ? 0.28 : 0), radius: 2, y: 1.5)
    }

    /// 落地后的最终微斜：按日期取值，每天固定 —— 不会因为 view 重建就晃到别的角度。
    private var finalTilt: Double {
        let choices = [-6.0, -2.0, 3.0, -4.0, 1.0, 5.0, -1.0]
        return choices[day % choices.count]
    }

    /// 空中初始角度：拉大一档，跟落地角度反向，掉进去会有个甩正的感觉。
    private var dropTilt: Double { -finalTilt * 2.5 }
}
