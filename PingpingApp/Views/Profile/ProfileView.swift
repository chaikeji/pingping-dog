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

    private var profile: DogProfile {
        if let existing = profiles.first { return existing }
        let created = DogProfile()
        context.insert(created)
        return created
    }

    var body: some View {
        ZStack {
            AppTheme.stageGray.ignoresSafeArea()

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

                Spacer(minLength: 0)

                DogStageView(profile: profile)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .onTapGesture(count: 2) { showStatusOverlay = true }

                Text(profile.ageText.isEmpty ? "未填生日" : profile.ageText)
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                    .padding(.top, 12)

                Spacer(minLength: 0)
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
    @State private var dragAngle: Double = 0
    @State private var committedAngle: Double = 0

    var body: some View {
        Group {
            if let modelURL = ModelStorage.resolve(profile.model3DLocalURL) {
                RealityView { content in
                    guard let entity = try? await ModelEntity(contentsOf: modelURL) else { return }
                    content.add(entity)
                } update: { content in
                    content.entities.first?.transform.rotation =
                        simd_quatf(angle: Float(Angle(degrees: dragAngle).radians), axis: [0, 1, 0])
                }
                .gesture(
                    DragGesture()
                        .onChanged { dragAngle = committedAngle + $0.translation.width * 0.6 }
                        .onEnded { _ in
                            withAnimation(.spring) { dragAngle = 0 }  // 松手回正
                            committedAngle = 0
                        }
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
