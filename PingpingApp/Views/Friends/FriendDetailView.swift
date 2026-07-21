import SwiftUI
import PhotosUI
import QuickLook

/// 狗朋友详情（PRD §5.2，Panora Batch 4）：
/// 顶部按 `modelStatus` 切换 → 3D 查看器 / 假 4 步 loading / 失败。
/// 中部信息卡（只读）+ 照片 section（保留）。底部换照片/重试。
///
/// 4 步进度假动画：`ThreeDModelGenerator` 里没打细粒度状态，UI 就自己按固定节拍走
/// 「上传 1s → 图生 10s → 转 USDZ 3s → 下载 (停在这)」——真的 `.ready` 由外面
/// 的 `modelStatus` 观察值切换到 3D viewer；`.failed` 也切走。整套只做视觉。
struct FriendDetailView: View {
    @Bindable var friend: DogFriend
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var showPhotoOptions = false
    @State private var isRegenerating = false
    @State private var fakeStep: FakeStep = .uploading
    @State private var spinnerRotation: Double = 0

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private var isLoading: Bool {
        friend.modelStatus == .queued || friend.modelStatus == .processing
    }

    var body: some View {
        ZStack {
            Panora.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 14) {
                        heroSlot
                        if isLoading { stepProgressCard }
                        infoCard
                        photoSection
                        actionButtons
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .quickLookPreview($previewURL)
        .photoSourcePicker(isPresented: $showPhotoOptions) { data in
            friend.avatarData = data
            runGeneration { await generator.generate(photoData: data, into: friend) }
        }
        // 假进度：view 出现 / 换狗友 / status 从别的状态切进 loading 时都重置一次。
        // .task(id:) 换 id 就自动重启任务。
        .task(id: fakeStepTaskKey) {
            guard isLoading else { return }
            await runFakeStepCycle()
        }
        // 旋转环无限旋转 —— 只在 loading 状态才启动一次动画。
        .onAppear {
            if isLoading {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    spinnerRotation = 360
                }
            }
        }
    }

    // 用「id + status」联合当 key：换狗友 / status 变化都触发 .task 重算。
    private var fakeStepTaskKey: String {
        "\(friend.id.uuidString)-\(friend.modelStatus.rawValue)"
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Text("好朋狗").font(.system(size: 15))
                }
                .foregroundStyle(Panora.textSecondary)
            }
            Spacer()
            Text(friend.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Panora.textPrimary)
            Spacer()
            // 右侧占位保持标题居中，跟左边宽度对齐
            Color.clear.frame(width: 60, height: 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - 顶部 Hero（按 status 切）

    @ViewBuilder
    private var heroSlot: some View {
        switch friend.modelStatus {
        case .ready:
            if let modelURL = ModelStorage.resolve(friend.model3DLocalURL) {
                readyViewer(modelURL: modelURL)
            } else {
                // .ready 但文件丢了：算失败处理。
                failedViewer(message: "模型文件丢失，需重新生成")
            }
        case .queued, .processing:
            loadingViewer
        case .failed:
            failedViewer(message: friend.modelErrorMessage ?? "生成失败")
        case .notStarted:
            notStartedViewer
        }
    }

    private func readyViewer(modelURL: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20)
                .fill(RadialGradient(
                    colors: [Color(hex: 0x262A31), Color(hex: 0x14161B)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 20, endRadius: 260
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
                )
            Model3DView(modelURL: modelURL, sizing: .screenFill(ratio: 0.64))
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            // 「拖动旋转」提示药丸，底部居中
            VStack {
                Spacer()
                Text("↻ 拖动旋转")
                    .font(.system(size: 11))
                    .foregroundStyle(Panora.textPrimary.opacity(0.75))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .panoraGlass(cornerRadius: 999)
                    .padding(.bottom, 12)
            }
            // 全屏按钮，右上
            Button { previewURL = modelURL } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Panora.textPrimary)
                    .frame(width: 32, height: 32)
                    .panoraGlass(cornerRadius: 10)
            }
            .padding(12)
        }
        .frame(height: 260)
    }

    private var loadingViewer: some View {
        ZStack {
            // 底：原照片模糊打底（如果有）
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x1C1F26), Color(hex: 0x14161B)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
                )
            if let data = friend.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.16)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: 0x0E0F12).opacity(0.5))
                    )
            }
            VStack(spacing: 18) {
                spinner
                VStack(spacing: 6) {
                    Text("正在生成 3D 模型…")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Panora.textPrimary)
                    Text("通常 1–3 分钟 · 可以先去别的页面\n好了会自动出现在这里")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Panora.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 300)
    }

    private var spinner: some View {
        ZStack {
            // 底环（20% 白，静止）
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 5)
            // 荧光绿弧：25% 长度旋转
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Panora.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(spinnerRotation))
                .shadow(color: Panora.lime.opacity(0.6), radius: 4)
            Text("🧊")
                .font(.system(size: 28))
        }
        .frame(width: 72, height: 72)
    }

    private func failedViewer(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Panora.coral)
            Text("生成失败")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Panora.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Panora.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Panora.darkCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
        )
    }

    private var notStartedViewer: some View {
        VStack(spacing: 10) {
            Text("🧊").font(.system(size: 38)).opacity(0.5)
            Text("尚未生成 3D 模型")
                .font(.system(size: 14))
                .foregroundStyle(Panora.textSecondary)
        }
        .frame(maxWidth: .infinity).frame(height: 260)
        .background(Panora.darkCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - 4 步进度卡

    private var stepProgressCard: some View {
        VStack(spacing: 14) {
            ForEach(FakeStep.allCases, id: \.self) { step in
                stepRow(step)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panoraCard(cornerRadius: 18)
    }

    private func stepRow(_ step: FakeStep) -> some View {
        let state = state(for: step)
        return HStack(spacing: 12) {
            stepDot(state: state)
            Text(step.label)
                .font(.system(size: 14))
                .foregroundStyle(state == .waiting ? Panora.textMuted : Panora.textPrimary)
            Spacer()
            Text(state.tag)
                .font(.system(size: 12))
                .foregroundStyle(state.tagColor)
        }
    }

    @ViewBuilder
    private func stepDot(state: StepState) -> some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(Panora.greenOK)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
        case .inProgress:
            Circle()
                .strokeBorder(Panora.lime, lineWidth: 2)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().fill(Panora.lime).frame(width: 6, height: 6)
                )
        case .waiting:
            Circle()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 2)
                .frame(width: 22, height: 22)
        }
    }

    private func state(for step: FakeStep) -> StepState {
        if step.rawValue < fakeStep.rawValue { return .done }
        if step == fakeStep { return .inProgress }
        return .waiting
    }

    // MARK: - 信息卡（可编辑，亲密度除外）
    //
    // spec 的 info card 是纯只读展示，但只读会让用户拼错名字后没法救 ——
    // 保留编辑能力，视觉贴 Panora 卡片风格（label 左 / 输入右对齐）。
    // 亲密度仍然只读、coral 700：它随遛狗遇见自动 +1，手改就废了。

    private var infoCard: some View {
        VStack(spacing: 0) {
            editRow(label: "名字") {
                TextField("", text: $friend.name,
                          prompt: Text("必填").foregroundColor(Panora.textFaint))
                    .font(.system(size: 15))
                    .foregroundStyle(Panora.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            divider
            editRow(label: "性别") {
                HStack(spacing: 6) {
                    genderPill("公")
                    genderPill("母")
                }
            }
            divider
            editRow(label: "年龄") {
                TextField("", text: $friend.ageText,
                          prompt: Text("如「约 3 岁」").foregroundColor(Panora.textFaint))
                    .font(.system(size: 15))
                    .foregroundStyle(Panora.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            divider
            editRow(label: "认识日期") {
                DatePicker("", selection: $friend.metDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
            }
            divider
            // 亲密度：只读，跟 spec 一致 —— coral 700。
            HStack {
                Text("♥ 亲密度")
                    .font(.system(size: 14))
                    .foregroundStyle(Panora.textSecondary)
                Spacer()
                Text("\(friend.intimacy)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Panora.coral)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Panora.darkCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
        )
    }

    private func editRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Panora.textSecondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func genderPill(_ value: String) -> some View {
        let selected = friend.gender == value
        return Button {
            friend.gender = selected ? "" : value
        } label: {
            Text(value)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Panora.lime : Panora.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(
                    selected ? Panora.lime.opacity(0.20) : Color.white.opacity(0.06),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
    }

    // MARK: - 照片 section（保留）

    @ViewBuilder
    private var photoSection: some View {
        if let data = friend.avatarData, let uiImage = UIImage(data: data) {
            VStack(alignment: .leading, spacing: 8) {
                Text("照片")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Panora.textMuted)
                    .padding(.leading, 4)
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Panora.cardBorder, lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - 换照片 / 重试按钮

    @ViewBuilder
    private var actionButtons: some View {
        if isRegenerating {
            HStack(spacing: 8) {
                ProgressView().tint(Panora.lime)
                Text("重新生成中…")
                    .font(.system(size: 14))
                    .foregroundStyle(Panora.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 10) {
                // 失败时先给「原图重试」—— 服务端多半跑完了，重试省额度。
                if friend.modelStatus == .failed, let photo = friend.avatarData {
                    Button {
                        runGeneration { await generator.retry(photoData: photo, into: friend) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("用原图重试")
                                .font(.system(size: 15, weight: .semibold))
                            Text("接着上次的进度，通常不额外消耗额度")
                                .font(.system(size: 11))
                                .foregroundStyle(Panora.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Panora.textPrimary)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                // 换照片：ready / failed 都能用；loading 时不显示，让用户等完再换。
                if friend.modelStatus == .ready || friend.modelStatus == .failed || friend.modelStatus == .notStarted {
                    Button {
                        showPhotoOptions = true
                    } label: {
                        Text(regenerateButtonLabel)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Panora.textPrimary.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var regenerateButtonLabel: String {
        switch friend.modelStatus {
        case .failed: return "换张照片重新生成"
        case .notStarted: return "选张照片开始生成"
        default: return "不满意？换张照片重新生成"
        }
    }

    // MARK: - 假 4 步循环

    private func runFakeStepCycle() async {
        fakeStep = .uploading
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard isLoading, !Task.isCancelled else { return }
        fakeStep = .generating
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        guard isLoading, !Task.isCancelled else { return }
        fakeStep = .converting
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard isLoading, !Task.isCancelled else { return }
        fakeStep = .downloading
        // 停在这一步。真的完成看 `modelStatus == .ready`，那时候整屏切走，本任务被取消。
    }

    // MARK: - 生成任务包一层，开/关 spinner

    private func runGeneration(_ work: @escaping () async -> Void) {
        Task {
            isRegenerating = true
            await work()
            isRegenerating = false
        }
    }
}

// MARK: - Fake step enum & state

private enum FakeStep: Int, CaseIterable {
    case uploading = 0
    case generating
    case converting
    case downloading

    var label: String {
        switch self {
        case .uploading: return "上传照片"
        case .generating: return "图生模型"
        case .converting: return "转 USDZ"
        case .downloading: return "下载缓存"
        }
    }
}

private enum StepState {
    case done, inProgress, waiting

    var tag: String {
        switch self {
        case .done: return "完成"
        case .inProgress: return "进行中"
        case .waiting: return "等待"
        }
    }

    var tagColor: Color {
        switch self {
        case .done: return Panora.textMuted
        case .inProgress: return Panora.lime
        case .waiting: return Panora.textFaint
        }
    }
}
