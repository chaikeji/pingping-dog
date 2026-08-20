import SwiftUI
import SwiftData
import Combine
import SDWebImageSwiftUI

/// 平平首页：纯白底、顶部状态通知壳、中间动态宠物、下方年龄、左上角徽章。
/// 数据录入不在此页（已取消「档案」入口），移到「完美的一天」的设置齿轮。
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [DogProfile]
    @Query private var vaccinationRecords: [VaccinationRecord]

    @State private var showStatusOverlay = false
    @State private var showVaccinations = false
    @State private var activeAction: ActivePetHomeAction?

    private var profile: DogProfile {
        if let existing = profiles.first { return existing }
        let created = DogProfile()
        context.insert(created)
        return created
    }

    private var displayName: String {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "平平" : name
    }

    private var hasVaccinationRecord: Bool {
        let ownerID = profile.id.uuidString
        return vaccinationRecords.contains { $0.ownerID == ownerID }
    }

    var body: some View {
        ZStack {
            AppTheme.stageGray.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    NotificationStrip()
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    HStack {
                        Button {
                            showVaccinations = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "syringe.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(hasVaccinationRecord ? Color.green : AppTheme.inkSub)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(hasVaccinationRecord ? "已接种" : "未接种")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppTheme.inkSub)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)

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
                    .frame(height: 66)

                    PetHomeStage(profile: profile, activeAction: activeAction)
                        // 按年龄文字 17pt 的三倍，形象和年龄整组上移 51pt。
                        .offset(y: -51)
                        .onTapGesture(count: 2) { showStatusOverlay = true }
                        .task(id: activeAction?.id) {
                            guard let playingAction = activeAction else { return }
                            try? await Task.sleep(for: .seconds(playingAction.action.playbackDuration))
                            guard !Task.isCancelled else { return }
                            activeAction = nil
                        }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .fullScreenCover(isPresented: $showStatusOverlay) {
            StatusVisualizationOverlay(onClose: { showStatusOverlay = false })
        }
        .fullScreenCover(isPresented: $showVaccinations) {
            VaccinationRecordsView(
                petName: displayName,
                ownerID: profile.id.uuidString
            )
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

    /// 按每个 WebP 第一帧的 Alpha 边界，对齐静态图的宽、高和中心点。
    var presentation: PetActionPresentation {
        switch self {
        case .idle: .init(scaleX: 1.020, scaleY: 1.009, offsetX: -0.001, offsetY: 0)
        case .happy: .init(scaleX: 2.098, scaleY: 1.121, offsetX: 0.342, offsetY: -0.037)
        case .sneeze: .init(scaleX: 1.911, scaleY: 1.062, offsetX: 0.005, offsetY: -0.007)
        case .surprised: .init(scaleX: 1.830, scaleY: 1.015, offsetX: 0.051, offsetY: -0.019)
        case .wave: .init(scaleX: 1.817, scaleY: 1.015, offsetX: 0.021, offsetY: -0.005)
        }
    }

    var playbackDuration: Double { self == .idle ? 5.05 : 4.05 }

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

private struct PetActionPresentation {
    let scaleX: CGFloat
    let scaleY: CGFloat
    /// 相对正方形舞台边长的偏移比例。
    let offsetX: CGFloat
    let offsetY: CGFloat
}

private struct ActivePetHomeAction: Identifiable {
    let id = UUID()
    let action: PetHomeAction
}

/// 静态图始终留在动画下面：WebP 解码完成前以及播放结束时都不会露出空白帧。
private struct PetHomeStage: View {
    let profile: DogProfile
    let activeAction: ActivePetHomeAction?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 36, geo.size.height - 56)
            let centerY = geo.size.height / 2

            ZStack {
                if let activeAction {
                    let presentation = activeAction.action.presentation
                    DogStageView(action: activeAction.action)
                        .frame(width: side, height: side)
                        .scaleEffect(x: presentation.scaleX, y: presentation.scaleY)
                        .offset(
                            x: side * presentation.offsetX,
                            y: side * presentation.offsetY
                        )
                        .id(activeAction.id)
                } else {
                    Image("pingping_static")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                }
            }
            .frame(width: side, height: side)
            // 静态图和全部动作共用同一个舞台，统一放大 10%，保持彼此校准关系不变。
            .scaleEffect(1.1)
            .position(x: geo.size.width / 2, y: centerY)

            Text(profile.ageText.isEmpty ? "未填生日" : profile.ageText)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .position(
                    x: geo.size.width / 2,
                    y: min(geo.size.height - 18, centerY + side / 2 + 20)
                )
        }
    }
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

    var body: some View {
        // 静态图已经常驻在下面；本地动画解码前 UIView 本身透明，
        // 因此无需等待 onSuccess。固定 true 可确保首次创建就开始播放。
        AnimatedImage(name: action.resourceName, isAnimating: .constant(true))
            .maxBufferSize(20 * 1_024 * 1_024)
            .customLoopCount(1)
            .pausable(false)
            .purgeable(true)
            .resizable()
            .scaledToFit()
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
