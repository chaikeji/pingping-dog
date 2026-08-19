import SwiftUI
import SwiftData
import Combine
import SDWebImageSwiftUI

/// 平平首页：纯白底、顶部状态通知壳、中间动态宠物、下方年龄、左上角徽章。
/// 数据录入不在此页（已取消「档案」入口），移到「完美的一天」的设置齿轮。
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [DogProfile]

    @State private var showStatusOverlay = false
    @State private var badgeWiggle = false
    @State private var activeAction: ActivePetHomeAction?
    /// 长按徽章 1s 打开遛狗诊断日志 —— 上次拍照回来数据丢的那次 bug 靠这个复盘。
    /// 挂在徽章上而不是单独摆按钮，是为了不打乱平平居中的视觉。
    @State private var showDebugLog = false

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
                        // 长按 1 秒打开遛狗诊断日志。挂在这里不新增可见按钮，
                        // 用户知道就能查、不知道也不影响视觉。
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 1.0).onEnded { _ in
                                showDebugLog = true
                            }
                        )
                        Spacer()
                        Menu {
                            ForEach(PetHomeAction.allCases) { action in
                                Button {
                                    // 新的播放 ID 让同一个动作也能连续重新触发。
                                    activeAction = ActivePetHomeAction(action: action)
                                } label: {
                                    Text(action.title)
                                }
                            }
                        } label: {
                            Label("动作", systemImage: "figure.play")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // 静态图/动作共用同一块舞台，并以年龄文字上方为底部基准。
                    VStack(spacing: 0) {
                        Group {
                            if let activeAction {
                                DogStageView(action: activeAction.action)
                                    .id(activeAction.id)
                            } else {
                                Image("pingping_static")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(.horizontal, 18)
                            }
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onTapGesture(count: 2) { showStatusOverlay = true }
                            .task(id: activeAction?.id) {
                                guard activeAction != nil else { return }
                                // 可灵导出的动作约 5 秒；播放器严格限制为一轮，
                                // 播完随即换回透明待机素材的静态首帧。
                                try? await Task.sleep(for: .seconds(5.2))
                                guard !Task.isCancelled else { return }
                                activeAction = nil
                            }

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
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .fullScreenCover(isPresented: $showStatusOverlay) {
            StatusVisualizationOverlay(onClose: { showStatusOverlay = false })
        }
        .sheet(isPresented: $showDebugLog) {
            SessionEventLogView()
        }
    }
}

/// 首页动作及本地文件名。菜单只显示已经随 App 打包的动作。
private enum PetHomeAction: String, CaseIterable, Identifiable {
    case idle
    case wave
    case happy
    case surprised
    case sneeze

    var id: String { rawValue }
    var resourceName: String { "zhangsan-\(rawValue)-alpha.webp" }

    var title: String {
        switch self {
        case .idle: "待机"
        case .wave: "招手"
        case .happy: "开心"
        case .surprised: "惊讶"
        case .sneeze: "打喷嚏"
        }
    }

}

private struct ActivePetHomeAction: Identifiable {
    let id = UUID()
    let action: PetHomeAction
}

/// 显示 [[SessionEventLog]] 的整份日志。带一个 ShareLink 让用户分享给我复盘，
/// 一个「清空」抹掉旧记录、方便下次干净复现。
struct SessionEventLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = SessionEventLog.readAll()

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("遛狗诊断日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        ShareLink(item: SessionEventLog.logFileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button("清空") {
                            SessionEventLog.clear()
                            content = SessionEventLog.readAll()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
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

/// 首页动态宠物。只在首页可见时解码和播放；切走 Tab 后暂停并清理帧缓存。
private struct DogStageView: View {
    let action: PetHomeAction
    @State private var isAnimating = false

    var body: some View {
        AnimatedImage(name: action.resourceName, isAnimating: $isAnimating)
            .maxBufferSize(20 * 1_024 * 1_024)
            .customLoopCount(1)
            .pausable(false)
            .purgeable(true)
            .resizable()
            .scaledToFit()
            .padding(.horizontal, 18)
            .onAppear { isAnimating = true }
            .onDisappear { isAnimating = false }
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
