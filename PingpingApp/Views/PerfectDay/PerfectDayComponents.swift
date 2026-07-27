import SwiftUI

// MARK: - 径向进度环（3D 立体轨道 + 沿弧渐变 + 末端高光球）
//
// 交接稿 design_handoff_ring/进度环-换样式.md：
// 1. 底层深色描边（比弧宽 ~7pt）做外沿
// 2. 中层内凹轨道 —— 上暗下亮竖向渐变，制造凹槽感
// 3. 进度弧沿弧向渐变：#2F5D1E → #6FAE2A → #D4F24A + 阴影 + 荧光辉光
// 4. 进度终点亮青柠小圆点带光晕，强化立体感
// 5. 刻度线 46 根挪到最上层，避免被不透明的深色轨道盖住

struct ProgressRing: View {
    let percent: Int
    // 270° 弧：底部留 90° 缺口给下面的小狗；起点 7:30 顺时针到 4:30。
    private let arcFraction: CGFloat = 0.75
    private let strokeWidth: CGFloat = 12
    /// 深色外描边比弧宽 7pt（交接稿 §2）。
    private let outlineExtra: CGFloat = 7
    /// 终点高光球颜色（交接稿 §4，#EAFF70）。
    private let endHighlightColor = Color(hex: 0xEAFF70)
    /// 进度渐变的最亮端色，也用作辉光颜色。
    private let arcHotColor = Color(hex: 0xD4F24A)

    private var progressFraction: CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }

    var body: some View {
        ZStack {
            // ① 最底层深色外描边（比弧宽 7pt）—— 立体外沿。
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(
                    Color(hex: 0x0A0B0D),
                    style: StrokeStyle(lineWidth: strokeWidth + outlineExtra, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            // ② 内凹轨道：上暗下亮的竖向渐变，做出凹槽的第一层深度。
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(
                    LinearGradient(
                        colors: [Color.black.opacity(0.60), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))

            // ③ 内投影 —— 深色轨道往下偏 2pt + 3pt 模糊，再用轨道 mask 裁在轨道范围内，
            // 效果是轨道顶部一圈更暗的凹陷阴影。SwiftUI 没有原生 inset shadow，这是替代方案。
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(Color.black.opacity(0.60),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .offset(y: 2)
                .blur(radius: 3)
                .mask(
                    Circle()
                        .trim(from: 0, to: arcFraction)
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(135))
                )
                .allowsHitTesting(false)

            // ④ 进度弧：沿弧向渐变（AngularGradient 的 0…270° 空间正好等于弧本身长度）。
            // AngularGradient 的 0° 起始在 3 点方向，加 rotationEffect(135°) 后被旋到 7:30，
            // 跟弧的物理起点对齐；270° 那端相应落在 4:30，也就是弧末端。
            Circle()
                .trim(from: 0, to: progressFraction * arcFraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(hex: 0x2F5D1E), location: 0.00),
                            .init(color: Color(hex: 0x6FAE2A), location: 0.45),
                            .init(color: arcHotColor,         location: 1.00),
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: Color.black.opacity(0.55), radius: 5, y: 3)
                .shadow(color: arcHotColor.opacity(0.40), radius: 8)
                .animation(.easeOut(duration: 0.6), value: percent)

            // ⑤ 末端高光球：亮青柠 + 6pt 光晕，浮在弧尽头。0% 时不画（否则会挂在起点闪一下）。
            if percent > 0 { endHighlightBall }

            // ⑥ 刻度线放最上：轨道现在是不透明的，之前放底层会被完全盖住。
            TickRing()
        }
    }

    /// 末端高光球。位置 = 弧末端角度 (135° + progress·270°) 上距圆心 r 处，
    /// 其中 r 是弧的 center-line 半径 = min(w,h)/2 - strokeWidth/2。
    private var endHighlightBall: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let r = side / 2 - strokeWidth / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let deg = 135.0 + Double(progressFraction) * 270.0
            let angle = deg * .pi / 180.0
            let x = center.x + CGFloat(cos(angle)) * r
            let y = center.y + CGFloat(sin(angle)) * r
            Circle()
                .fill(endHighlightColor)
                .frame(width: strokeWidth, height: strokeWidth)
                .shadow(color: endHighlightColor.opacity(0.9), radius: 6)
                .position(x: x, y: y)
                .animation(.easeOut(duration: 0.6), value: percent)
        }
        .allowsHitTesting(false)
    }
}

/// 环内圈刻度：只沿 270° 弧铺 46 根，跟着弧的缺口一起断在底部。
/// 之前刻度画在环外（r → r+6），用户要求改回原 UI —— 刻度应在环里（从环的内边向圆心方向延伸）。
/// 环 stroke 宽 12，中线半径 r，内边 r-6；刻度外端贴内边、往圆心方向延伸 6pt（大格）或 3pt（小格）。
private struct TickRing: View {
    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Path { path in
                for i in 0...45 {
                    let degrees: Double = 135.0 + Double(i) * 6.0
                    let angle: Double = degrees * .pi / 180.0
                    let cosA: CGFloat = CGFloat(cos(angle))
                    let sinA: CGFloat = CGFloat(sin(angle))
                    // 刻度外端 = 环的内边（r - stroke/2）；内端向圆心方向延伸。
                    let outer: CGFloat = r - 6
                    let length: CGFloat = (i % 5 == 0) ? 6 : 3
                    let inner: CGFloat = outer - length
                    let start = CGPoint(x: center.x + cosA * inner, y: center.y + sinA * inner)
                    let end = CGPoint(x: center.x + cosA * outer, y: center.y + sinA * outer)
                    path.move(to: start)
                    path.addLine(to: end)
                }
            }
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }
}

// MARK: - 日期条

/// 日期条：小太阳展示当天成绩，**点任意一天进到那天的整页**（跟今天同一套 UI，
/// 只是不能打卡）。没记录的日子也能点 —— 「那天什么都没做」本身也是信息。
/// 整条左滑看历史，今天高亮。
struct DateStrip: View {
    let days: [Date]
    let tierProvider: (Date) -> SunTier
    let onSelect: (Date) -> Void

    private let today = PetDay.start()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // 历史会一直长下去，用 Lazy 的，不然攒够几百天每次进页面都要全渲染一遍。
                LazyHStack(spacing: 14) {
                    ForEach(days, id: \.self) { day in
                        Button { onSelect(day) } label: { dayCell(day) }
                            .buttonStyle(.plain)
                            .id(day)
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
                .monospacedDigit()
                .foregroundStyle(isToday ? Panora.textPrimary : Color.white.opacity(0.55))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            isToday ? Color.white.opacity(0.12) : .clear,
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
        // 老代码是 AppTheme.inkSub（暗灰）—— 在 Panora 深色底上会几乎看不见。
        // 换成 white 40%，跟设计稿档位色一致，SF sun.max.fill 的画法本身不动。
        case .gray: return Color.white.opacity(0.4)
        }
    }
}

// MARK: - 挑战说明弹窗（点进度环中心 → 弹）

/// Panora 交接稿 §③：
/// `.medium` detent，自绘拖动条 + 居中标题（无右上「完成」）+ 四档行 + 分隔 + 两段说明（末句 lime）+ 底部大绿 CTA。
/// 用 `.presentationDragIndicator(.hidden)` 关掉系统默认的胶囊，画自己的 40×5 拖动条以贴设计尺寸。
struct ChallengeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部自绘拖动条：40×5，white 22%，3pt 圆角，居中。
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 40, height: 5)
                    .padding(.top, 14)
                    .padding(.bottom, 20)

                // 居中标题（无右上「完成」）。
                Text("完美一天挑战")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Panora.textPrimary)
                    .padding(.bottom, 22)

                // 四档行：徽章 24 + 档名 15 bold + 右侧区间 14。每行底 0.5pt 分隔。
                VStack(spacing: 0) {
                    tierRow(.gold, "金", "80–100%")
                    tierRow(.silver, "银", "60–80%")
                    tierRow(.bronze, "铜", "40–60%")
                    tierRow(.gray, "灰", "<40%")
                }

                // 段间分隔：0.5pt white 10%。
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.vertical, 18)

                // 两段说明。第二段末句"身体好的日子才可能冲金。"用 lime 高亮。
                VStack(alignment: .leading, spacing: 12) {
                    Text("完美值 = 当天完成的日常习惯 ÷ 已启用习惯。")
                        .foregroundStyle(Color.white.opacity(0.62))
                    (
                        Text("身体（健康 / 清洁）是天花板：任一不达标，当天完美值最高只到银；都不达标最高只到铜。")
                            .foregroundStyle(Color.white.opacity(0.62))
                        + Text("身体好的日子才可能冲金。")
                            .foregroundStyle(Panora.lime)
                    )
                }
                .font(.system(size: 14))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                // 底部大 CTA：荧光绿「知道了」。
                Button { dismiss() } label: {
                    Text("知道了")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Panora.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Panora.lime, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Panora.lime.opacity(0.28), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Panora.appBackground)
    }

    private func tierRow(_ tier: SunTier, _ name: String, _ range: String) -> some View {
        HStack(spacing: 12) {
            SunBadge(tier: tier).frame(width: 24, height: 24)
            Text(name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Panora.textPrimary)
            Spacer()
            Text(range)
                .font(.system(size: 14))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
        // 行底 0.5pt 分隔，Rectangle 顶到左右两侧，跟设计一致。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}
