import SwiftUI
import UIKit

/// 遛狗回顾（月卡）—— Batch 1 §⑤：
/// 按月聚合 WalkRoute，竖排全幅照片月卡。入口 = 遛狗页里程柱状卡整卡点击。
/// 底部悬浮玻璃 Tab（原型有）暂不实现，因为要动全局 RootTabView；留给后面的 Batch。
struct MonthlyReviewGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let routes: [WalkRoute]

    @State private var selectedYear: Int

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
                                MonthPhotoCard(
                                    month: month,
                                    routes: routesIn(month)
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollContentBackground(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Panora.textPrimary)
                }
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

/// 一张月卡：底图 = 当月代表照片（没有就渐变），左下超大月份数字，左上玻璃药丸。
private struct MonthPhotoCard: View {
    let month: DateComponents
    let routes: [WalkRoute]

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            // 底部渐变，让月份数字压在上面还能看清。
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            monthNumeral
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

    @ViewBuilder
    private var background: some View {
        if let image = representativeImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Panora.darkCard
        }
    }

    private var monthNumeral: some View {
        VStack {
            Spacer()
            HStack {
                Text(String(format: "%d月", month.month ?? 0))
                    .font(.system(size: 78, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.88))
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

    /// 当月第一条有照片的记录的第一张照片；没有就 nil。
    private var representativeImage: UIImage? {
        for r in routes {
            if let data = r.photosData.first, let img = UIImage(data: data) {
                return img
            }
        }
        return nil
    }
}
