import SwiftUI
import SwiftData
import RealityKit
import Combine

/// 平平首页：灰底、顶部状态通知壳、中间可拖 360° 静态模型、下方年龄、左上角徽章。
/// 数据录入不在此页（已取消「档案」入口），移到「完美的一天」的设置齿轮。
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [DogProfile]

    @State private var showStatusOverlay = false
    @State private var badgeWiggle = false

    /// 模型 + 年龄文字整组上移，占页面高度的比例。
    private static let stageLiftRatio: CGFloat = 0.20
    /// 整组横向微调，负数往左。跟 ageTextNudgeX 叠加：这个挪模型和文字，那个只挪文字。
    private static let stageNudgeX: CGFloat = -10
    /// 年龄文字的微调，正数往右 / 往下。见下方注释：只能真机上比着填。
    /// 字号 17，所以「两个字」= 34、「一个字」= 17。
    /// 用 offset 而不是 padding：padding 会占布局高度，把画布压矮、平平跟着缩。
    private static let ageTextNudgeX: CGFloat = 19
    private static let ageTextNudgeY: CGFloat = 17

    private var profile: DogProfile {
        if let existing = profiles.first { return existing }
        let created = DogProfile()
        context.insert(created)
        return created
    }

    var body: some View {
        ZStack {
            AppTheme.stageGray.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    NotificationStrip()
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    // 徽章在通知栏「下方」，靠左；不再盖住通知栏。
                    HStack {
                        Button {
                            badgeWiggle = true
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.35)) { badgeWiggle = false }
                        } label: {
                            Image("pingping_badge")
                                .resizable().scaledToFit()
                                .frame(height: 56)
                                .scaleEffect(badgeWiggle ? 1.25 : 1)
                                .rotationEffect(.degrees(badgeWiggle ? 8 : 0))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // 舞台 + 年龄文字是一整组，一起往上抬。
                    //
                    // 抬法用 offset 而不是「底下垫空白」：垫空白会把画布压矮，
                    // 平平是按画布高度的七成算的，会跟着缩小 —— 位置和大小得解耦。
                    VStack(spacing: 0) {
                        // 舞台吃掉剩余的**全部**空间。别再给它写死高度：写死就等于
                        // 给平平画了个框，模型一大就被裁成一条硬边，凭空多出一道水平线。
                        // 大小由模型自己按画布比例定（见 Sizing.fitHeight），不是靠框去卡。
                        DogStageView(profile: profile)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture(count: 2) { showStatusOverlay = true }

                        // 紧跟在画布下沿 = 紧跟在模型的裁切线下面。
                        //
                        // nudgeX 是横向微调：模型是按包围盒居中的，可平平顶着狗、
                        // 狗又偏向一侧，包围盒中心因此不等于 T 恤（最下沿）的中心，
                        // 文字看着就没对齐。代码拿不到「T 恤在哪」，只能真机上比着填。
                        Text(profile.ageText.isEmpty ? "未填生日" : profile.ageText)
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.ink)
                            .padding(.top, 8)
                            .offset(x: Self.ageTextNudgeX, y: Self.ageTextNudgeY)
                    }
                    .offset(x: Self.stageNudgeX, y: -geo.size.height * Self.stageLiftRatio)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .fullScreenCover(isPresented: $showStatusOverlay) {
            StatusVisualizationOverlay(onClose: { showStatusOverlay = false })
        }
    }
}

/// iOS 26 的原生液态玻璃；更早的系统退回材质模糊。
private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.4)))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

/// 顶部「状态通知」区（PRD §5.1）：由 NotificationEngine 从护理/健康/遛狗状态派生，
/// 按优先级轮播（每 3 秒一条），右侧三角展开完整列表；无待办时整条隐藏。
private struct NotificationStrip: View {
    @Query private var cycles: [CareCycle]
    @Query private var conditions: [HealthCondition]
    @Query private var walks: [WalkRoute]

    @State private var index = 0
    @State private var showList = false

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var items: [StatusNotification] {
        NotificationEngine.build(cycles: cycles, conditions: conditions, walks: walks)
    }

    var body: some View {
        let items = self.items
        if items.isEmpty {
            EmptyView()  // 空态：整条隐藏，下方形象+徽章+年龄自然居中
        } else {
            let safeIndex = min(index, items.count - 1)
            HStack(spacing: 10) {
                Circle().fill(AppTheme.coral).frame(width: 7, height: 7)
                Text(items[safeIndex].text)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .id(safeIndex)
                    .transition(.opacity)
                Spacer()
                Button { showList = true } label: {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSub)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .glassCard(cornerRadius: 22)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut) { index = (safeIndex + 1) % items.count }
            }
            .sheet(isPresented: $showList) {
                NavigationStack {
                    List(items) { Text($0.text) }
                        .navigationTitle("待办提醒")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
        }
    }
}

/// 中间平平形象：可拖动 360° 查看的静态 3D 模型（松手回正，不自动播放动画）。
/// 有本地 USDZ 就渲染模型，否则显示头像 / 占位。
private struct DogStageView: View {
    let profile: DogProfile

    var body: some View {
        Group {
            if let modelURL = ModelStorage.resolve(profile.model3DLocalURL) {
                // 露出来的平平占画布高度七成，两边各留一成余量。
                //
                // bottomCrop 是**模型总高**的比例，模型约 390pt 高，所以 1% 才 4pt。
                // 真机上一路比下来 15% → 5% → 3% → 2% 全是「切多了」，索性归零，
                // 先拿「完全不裁」当参照点。要重新切的话，步子得迈大些才看得出来。
                Model3DView(
                    modelURL: modelURL,
                    sizing: .fitHeight(heightRatio: 0.7, maxWidthRatio: 0.9, bottomCrop: 0)
                )
            } else if let data = profile.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else {
                Image(systemName: "pawprint.circle.fill")
                    .resizable().scaledToFit().frame(width: 120, height: 120)
                    .foregroundStyle(AppTheme.inkSub.opacity(0.5))
            }
        }
    }
}

/// 双击形象弹出的「今日状态可视化」——本期占位壳，真实引线标注待联动阶段。
private struct StatusVisualizationOverlay: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "pawprint.circle").font(.system(size: 60)).foregroundStyle(AppTheme.inkSub)
                Text("今日状态可视化").font(.headline)
                Text("这里会按平平当前的健康状况和逾期护理项\n在身体轮廓上动态引线标注（待联动阶段）")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("关闭", action: onClose).padding(.top, 8)
            }
            .padding(40)
        }
    }
}
