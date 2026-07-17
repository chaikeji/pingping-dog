import SwiftUI

// MARK: - 径向进度环（刻度 + 荧光弧）

struct ProgressRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            TickRing()
            Circle()
                .stroke(AppTheme.inkSub.opacity(0.12), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(AppTheme.lime, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(135))  // 起点在左下角，顺时针填充
                .shadow(color: AppTheme.lime.opacity(0.5), radius: 6)
                .animation(.easeOut(duration: 0.6), value: percent)
        }
    }
}

/// 环外圈一圈细刻度。
private struct TickRing: View {
    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Path { path in
                for i in 0..<60 {
                    let angle = Double(i) / 60 * 2 * .pi
                    let outer = r + 6
                    let inner = r + (i % 5 == 0 ? 0 : 3)
                    path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                }
            }
            .stroke(AppTheme.inkSub.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - 日期条

/// 日期条（PRD §5.4）：小太阳仅展示当天成绩，**点单个不打开详情**，整条**左滑看历史**。
/// 今天高亮，其余只读。
struct DateStrip: View {
    let days: [Date]
    let tierProvider: (Date) -> SunTier

    private let today = PetDay.start()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day).id(day)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear { proxy.scrollTo(today, anchor: .trailing) }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = day == today
        let dayNum = Calendar.current.component(.day, from: day)
        return VStack(spacing: 4) {
            SunBadge(tier: tierProvider(day))
                .frame(width: 30, height: 30)
            Text("\(dayNum)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? AppTheme.ink : AppTheme.inkSub)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            isToday ? AppTheme.inkSub.opacity(0.14) : .clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}

/// 小太阳徽章，颜色随档位。
struct SunBadge: View {
    let tier: SunTier

    var body: some View {
        Image(systemName: "sun.max.fill")
            .resizable().scaledToFit()
            .foregroundStyle(color)
            .opacity(tier == .gray ? 0.35 : 1)
    }

    private var color: Color {
        switch tier {
        case .gold: return AppTheme.amber
        case .silver: return Color(hex: 0xB8BCC2)
        case .bronze: return Color(hex: 0xCD7F32)
        case .gray: return AppTheme.inkSub
        }
    }
}

// MARK: - 挑战说明弹窗（ⓘ）

struct ChallengeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("怎么算「完美的一天」").font(.title3.bold())

                    tierRow(.gold, "金", "80–100%")
                    tierRow(.silver, "银", "60–80%")
                    tierRow(.bronze, "铜", "40–60%")
                    tierRow(.gray, "灰", "<40%")

                    Divider().padding(.vertical, 4)

                    Text("完美值 = 当天完成的日常习惯 ÷ 已启用习惯。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("身体（健康 / 清洁）是天花板：任一不达标，当天完美值最高只到银；都不达标最高只到铜。身体好的日子才可能冲金。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func tierRow(_ tier: SunTier, _ name: String, _ range: String) -> some View {
        HStack(spacing: 12) {
            SunBadge(tier: tier).frame(width: 26, height: 26)
            Text(name).font(.system(size: 15, weight: .bold))
            Spacer()
            Text(range).font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
