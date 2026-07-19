import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// 完美的一天的设置齿轮：承接首页取消档案后无处安放的全部录入口。
struct PerfectDaySettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var profiles: [DogProfile]
    @Query private var cycles: [CareCycle]
    @Query private var conditions: [HealthCondition]
    @Query(sort: \CareHabit.sortOrder) private var habits: [CareHabit]

    @State private var pickerItem: PhotosPickerItem?
    @State private var showUSDZImporter = false
    @State private var showModelPhotoOptions = false
    @State private var isGeneratingModel = false

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())
    @State private var newConditionName = ""
    @State private var newHabitName = ""
    @State private var newHabitEmoji = "✨"

    private var profile: DogProfile {
        if let existing = profiles.first { return existing }
        let created = DogProfile()
        context.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                model3DSection
                cyclesSection(title: "清洁", category: .clean)
                cyclesSection(title: "健康 · 周期", category: .health)
                conditionsSection
                habitsSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task(id: pickerItem) {
                guard let pickerItem, let data = try? await pickerItem.loadTransferable(type: Data.self) else { return }
                profile.avatarData = data
            }
            .fileImporter(isPresented: $showUSDZImporter, allowedContentTypes: [.usdz]) { result in
                if case .success(let url) = result { importUSDZ(from: url) }
            }
            .photoSourcePicker(isPresented: $showModelPhotoOptions) { data in
                profile.avatarData = data
                Task {
                    isGeneratingModel = true
                    await generator.generate(photoData: data, into: profile)
                    isGeneratingModel = false
                }
            }
        }
    }

    // MARK: - 平平资料

    @ViewBuilder private var profileSection: some View {
        Section("平平资料") {
            TextField("名字", text: Binding(get: { profile.name }, set: { profile.name = $0 }))
            TextField("品种", text: Binding(get: { profile.breed }, set: { profile.breed = $0 }))
            DatePicker("生日", selection: Binding(
                get: { profile.birthday ?? .now }, set: { profile.birthday = $0 }
            ), displayedComponents: .date)
            PhotosPicker("选择头像", selection: $pickerItem, matching: .images)
        }
    }

    // MARK: - 平平的 3D 形象

    /// 两条路并存：自己有 USDZ 就直接导入；没有就选张照片走 Tripo 生成。
    /// 生成链路和狗朋友完全共用，所以那边修过的超时、断点续传、不重复扣额度这些在这里同样生效。
    @ViewBuilder private var model3DSection: some View {
        Section("平平的 3D 形象") {
            switch profile.modelStatus {
            case .ready:
                if ModelStorage.resolve(profile.model3DLocalURL) == nil {
                    Label("模型文件丢失，需重新生成", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("已就绪，首页显示的就是它", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            case .processing, .queued:
                Label("生成中…", systemImage: "hourglass")
            case .failed:
                Label("生成失败", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if let message = profile.modelErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            case .notStarted:
                EmptyView()
            }

            if isGeneratingModel {
                HStack {
                    ProgressView()
                    Text("生成中…（约两三分钟，别退出 App）")
                }
            } else {
                // 失败时优先原图重试：服务端多半已经跑完，接着上次的进度不用再花额度。
                if profile.modelStatus == .failed, let photo = profile.avatarData {
                    Button {
                        Task {
                            isGeneratingModel = true
                            await generator.retry(photoData: photo, into: profile)
                            isGeneratingModel = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("用原图重试")
                            Text("接着上次的进度，通常不额外消耗额度")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("选张照片生成 3D（同时用作头像）") { showModelPhotoOptions = true }
                Button(ModelStorage.resolve(profile.model3DLocalURL) == nil
                       ? "或导入现成的 USDZ" : "更换现成的 USDZ") {
                    showUSDZImporter = true
                }
            }
        }
    }

    // MARK: - 周期护理（清洁 / 健康）

    private func cyclesSection(title: String, category: CareCategory) -> some View {
        Section(title) {
            ForEach(cycles.filter { $0.type.category == category }) { cycle in
                cycleRow(cycle)
            }
        }
    }

    private func cycleRow(_ cycle: CareCycle) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cycle.type.displayName)
                Text(cycle.isOverdue ? "已逾期" : "正常")
                    .font(.caption)
                    .foregroundStyle(cycle.isOverdue ? AppTheme.coral : AppTheme.greenOK)
            }
            Spacer()
            Button("今天做了") { cycle.lastDoneDate = .now }
                .font(.caption).buttonStyle(.bordered)
        }
    }

    // MARK: - 健康状况

    @ViewBuilder private var conditionsSection: some View {
        Section("健康状况") {
            ForEach(conditions) { condition in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(condition.name).strikethrough(condition.healed)
                        Text(condition.foundDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(condition.healed ? "已痊愈" : "标记痊愈") { condition.healed.toggle() }
                        .font(.caption).buttonStyle(.bordered)
                }
            }
            .onDelete { indexSet in
                for i in indexSet { context.delete(conditions[i]) }
            }
            HStack {
                TextField("新增疾病 / 症状", text: $newConditionName)
                Button("添加") {
                    guard !newConditionName.isEmpty else { return }
                    context.insert(HealthCondition(name: newConditionName))
                    newConditionName = ""
                }.disabled(newConditionName.isEmpty)
            }
        }
    }

    // MARK: - 日常习惯

    @ViewBuilder private var habitsSection: some View {
        Section("日常习惯（完美的一天）") {
            ForEach(habits) { habit in
                HStack {
                    Text(habit.emoji)
                    Text(habit.name)
                    if habit.isAuto {
                        Text("自动").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AppTheme.inkSub.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { habit.enabled }, set: { habit.enabled = $0 }))
                        .labelsHidden()
                }
            }
            .onDelete { indexSet in
                for i in indexSet where !habits[i].isAuto { context.delete(habits[i]) }
            }
            HStack {
                TextField("emoji", text: $newHabitEmoji).frame(width: 44)
                TextField("新增习惯", text: $newHabitName)
                Button("添加") {
                    guard !newHabitName.isEmpty else { return }
                    let order = (habits.map(\.sortOrder).max() ?? 0) + 1
                    context.insert(CareHabit(name: newHabitName, emoji: newHabitEmoji, sortOrder: order))
                    newHabitName = ""; newHabitEmoji = "✨"
                }.disabled(newHabitName.isEmpty)
            }
        }
    }

    // MARK: - USDZ 导入

    private func importUSDZ(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let dest = try ModelStorage.destination(ownerID: profile.id)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            profile.model3DLocalURL = dest
            // 手动导入的也要标成 ready，否则界面会一直停在「未开始 / 上次失败」的状态。
            profile.modelStatus = .ready
            profile.modelErrorMessage = nil
        } catch {
            // 导入失败静默忽略；真机上可加 toast
        }
    }
}
