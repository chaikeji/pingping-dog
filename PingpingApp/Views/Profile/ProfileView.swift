import SwiftUI
import SwiftData
import PhotosUI
import RealityKit

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [DogProfile]
    @State private var isEditing = false
    @State private var isGeneratingWalk = false

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())

    private var profile: DogProfile {
        if let existing = profiles.first { return existing }
        let created = DogProfile()
        context.insert(created)
        return created
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        heroView
                        Text(profile.name).font(.title2.bold())
                        Text(profile.breed.isEmpty ? "未填写品种" : profile.breed)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                if let birthday = profile.birthday {
                    Section("生日") {
                        Text(birthday.formatted(date: .long, time: .omitted))
                    }
                }
                walkingModelSection
            }
            .navigationTitle("平平档案")
            .toolbar {
                Button("编辑") { isEditing = true }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(profile: profile)
            }
        }
    }

    @ViewBuilder
    private var heroView: some View {
        if profile.modelStatus == .ready, let modelURL = profile.model3DLocalURL {
            WalkingModelView(modelURL: modelURL)
                .frame(width: 180, height: 180)
        } else if let data = profile.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
                .frame(width: 96, height: 96).clipShape(Circle())
        } else {
            Image(systemName: "pawprint.circle.fill")
                .resizable().frame(width: 96, height: 96).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var walkingModelSection: some View {
        Section("会走路的平平") {
            switch profile.modelStatus {
            case .ready:
                Label("已生成，首页头像会自动循环走路动画", systemImage: "checkmark.circle").foregroundStyle(.green)
                regenerateButton(title: "换张照片重新生成")
            case .queued, .processing:
                HStack {
                    ProgressView()
                    Text("生成中，包含绑骨+动作重定向，可能要几分钟…")
                }
            case .failed:
                Label("生成失败", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                if let message = profile.modelErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                regenerateButton(title: "换张照片重试")
            case .notStarted:
                Text("用头像照片生成一个会在首页走路的 3D 平平，只需要生成一次。")
                    .font(.caption).foregroundStyle(.secondary)
                if profile.avatarData != nil {
                    Button("生成会走路的平平") { startGeneration() }
                        .disabled(isGeneratingWalk)
                } else {
                    Text("先在「编辑」里设置一张头像照片").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func regenerateButton(title: String) -> some View {
        Button(title) { isEditing = true }
    }

    private func startGeneration() {
        guard let avatarData = profile.avatarData else { return }
        isGeneratingWalk = true
        Task {
            await generator.generateWalkingLoop(photoData: avatarData, into: profile)
            isGeneratingWalk = false
        }
    }
}

/// 用 RealityKit 加载 USDZ 并循环播放里面烘焙好的走路动画。
private struct WalkingModelView: View {
    let modelURL: URL

    var body: some View {
        RealityView { content in
            guard let entity = try? await ModelEntity(contentsOf: modelURL) else { return }
            if let animation = entity.availableAnimations.first {
                entity.playAnimation(animation.repeat())
            }
            content.add(entity)
        }
    }
}

private struct ProfileEditView: View {
    @Bindable var profile: DogProfile
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名字", text: $profile.name)
                TextField("品种", text: $profile.breed)
                DatePicker(
                    "生日",
                    selection: Binding(get: { profile.birthday ?? .now }, set: { profile.birthday = $0 }),
                    displayedComponents: .date
                )
                PhotosPicker("选择头像", selection: $pickerItem, matching: .images)
            }
            .navigationTitle("编辑档案")
            .toolbar {
                Button("完成") { dismiss() }
            }
            .task(id: pickerItem) {
                guard let pickerItem, let rawData = try? await pickerItem.loadTransferable(type: Data.self) else { return }
                // 头像同时也是生成 3D 模型的原图，Tripo 只收 JPEG/PNG，统一转成 JPEG。
                if let uiImage = UIImage(data: rawData), let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                    profile.avatarData = jpegData
                }
            }
        }
    }
}
