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
            Button(profile.model3DLocalURL == nil ? "导入平平 3D 模型（USDZ）" : "更换 3D 模型（USDZ）") {
                showUSDZImporter = true
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
        let dest = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(profile.id.uuidString).usdz")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            profile.model3DLocalURL = dest
        } catch {
            // 导入失败静默忽略；真机上可加 toast
        }
    }
}
