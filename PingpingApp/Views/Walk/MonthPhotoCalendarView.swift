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
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
            spacing: 6
        ) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day: day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let entry = photoEntry(for: day)
        ZStack {
            // 底：灰色圆角格子。有贴纸/照片时被盖住，没内容时露出来 + 显示日期。
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))

            if let sticker = entry.sticker {
                // 优先级 1：抠好的贴纸（透明 PNG + 已烘白描边）。带从天上掉下来的动画。
                StickerDropView(image: sticker, day: day)
                    .padding(2) // 贴纸稍微内缩，让白描边不贴到格子边
                    .overlay(alignment: .topTrailing) { countBadge(entry.count) }
            } else if let photo = entry.fallbackPhoto {
                // 优先级 2：贴纸还没抠好 / 抠图失败，退回原图缩略图。
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topTrailing) { countBadge(entry.count) }
            } else {
                // 优先级 3：这一天没照片，露日期数字。
                Text("\(day)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Panora.textMuted)
                    .monospacedDigit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
        /// 抠好的透明贴纸（首选，会带描边 + 掉落动画）。
        let sticker: UIImage?
        /// 没贴纸时的退化：当天照片最多那次的第一张原图。
        let fallbackPhoto: UIImage?
        /// 当天所有 route 的照片张数之和 —— 徽章用它，不是 route 数。
        let count: Int
    }

    /// 当天露什么：
    /// 1. 有 route 已经抠好 cutoutData → 用那张贴纸；多张都抠好了挑 photoScore 最高那次
    /// 2. 都没抠好 → 退化用「照片最多那次」的第一张原图占位
    /// 3. 一张照片都没 → sticker/fallback 都 nil，格子退化为日期数字
    private func photoEntry(for day: Int) -> DayEntry {
        let cal = Calendar.current
        let dayRoutes = routes.filter { cal.component(.day, from: $0.startDate) == day }

        var totalPhotos = 0
        var stickerCandidate: (walk: WalkRoute, score: Double)?
        var fallbackWalk: WalkRoute?

        for r in dayRoutes {
            totalPhotos += r.photosData.count

            if r.cutoutData != nil {
                // 分数拿不到（老库 photoScores 可能是空的）就当 0 参与比较，反正只关心相对大小。
                let bestScore = r.photoScores.max() ?? 0
                if (stickerCandidate?.score ?? -1) < bestScore {
                    stickerCandidate = (r, bestScore)
                }
            }
            if (fallbackWalk?.photosData.count ?? 0) < r.photosData.count {
                fallbackWalk = r
            }
        }

        let stickerImg: UIImage? = stickerCandidate?.walk.cutoutData.flatMap { UIImage(data: $0) }
        let fallbackImg: UIImage? = fallbackWalk?.photosData.first.flatMap { UIImage(data: $0) }
        return DayEntry(sticker: stickerImg, fallbackPhoto: fallbackImg, count: totalPhotos)
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
private struct StickerDropView: View {
    let image: UIImage
    let day: Int
    @State private var landed = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .rotationEffect(.degrees(landed ? finalTilt : dropTilt))
            .offset(y: landed ? 0 : -60)
            .opacity(landed ? 1 : 0)
            .shadow(color: .black.opacity(landed ? 0.28 : 0), radius: 2, y: 1.5)
            .onAppear {
                // 按天错开一点：整月一起「哗啦啦」比同帧砸下来好看。
                let delay = Double(day % 10) * 0.04
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(delay)) {
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
