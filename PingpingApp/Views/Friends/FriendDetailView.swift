import SwiftUI
import PhotosUI
import QuickLook

struct FriendDetailView: View {
    @Bindable var friend: DogFriend
    @State private var previewURL: URL?
    @State private var showPhotoOptions = false
    @State private var isRegenerating = false

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())
    private static let genders = ["公", "母"]

    var body: some View {
        Form {
            // 3D 模型放最前面：进来第一眼就是模型本身，不用再点一下才看得到。
            if let modelURL = ModelStorage.resolve(friend.model3DLocalURL) {
                Section {
                    Model3DView(modelURL: modelURL)
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                    Button {
                        previewURL = modelURL
                    } label: {
                        Label("全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            if let data = friend.avatarData, let uiImage = UIImage(data: data) {
                Section("照片") {
                    Image(uiImage: uiImage).resizable().scaledToFit()
                }
            }
            // 建档之后还能改：名字打错、性别看走眼、年龄后来问到了主人，都很常见。
            Section("信息") {
                TextField("名字", text: $friend.name)
                Picker("性别", selection: $friend.gender) {
                    Text("未填").tag("")
                    ForEach(Self.genders, id: \.self) { Text($0).tag($0) }
                }
                TextField("年龄（如「约 3 岁」）", text: $friend.ageText)
                DatePicker("认识日期", selection: $friend.metDate, displayedComponents: .date)
                // 亲密度只读：它由遛狗时遇见自动 +1，手填就失去意义了。
                LabeledContent("亲密度", value: "\(friend.intimacy)")
            }
            Section("3D 模型") {
                switch friend.modelStatus {
                case .ready:
                    // 模型本身已经在最上面那个 Section 渲染了，这里只交代状态。
                    // 按当前容器解析，重装后旧的绝对路径不能直接用；解析不到说明文件没了。
                    if ModelStorage.resolve(friend.model3DLocalURL) == nil {
                        Label("模型文件丢失，需重新生成", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                case .processing, .queued:
                    Label("生成中…", systemImage: "hourglass")
                case .failed:
                    Label("生成失败", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    if let message = friend.modelErrorMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                case .notStarted:
                    Text("未提交建模")
                }

                if isRegenerating {
                    HStack {
                        ProgressView()
                        Text("重新生成中…")
                    }
                } else {
                    // 失败时优先给「原图重试」：多数失败是网络断在下载那步，
                    // 而服务端的结果还留着，重试能直接接上、不用再花额度。
                    if friend.modelStatus == .failed, let photo = friend.avatarData {
                        Button {
                            runGeneration { await generator.retry(photoData: photo, into: friend) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("用原图重试")
                                Text("接着上次的进度，通常不额外消耗额度")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    // 不满意/失败了都能换张照片重新生成，不用删掉朋友重建。
                    if friend.modelStatus == .ready || friend.modelStatus == .failed {
                        Button(friend.modelStatus == .failed ? "换张照片重新生成" : "不满意？换张照片重新生成") {
                            showPhotoOptions = true
                        }
                    }
                }
            }
        }
        .navigationTitle(friend.name)
        .quickLookPreview($previewURL)
        .photoSourcePicker(isPresented: $showPhotoOptions) { data in
            friend.avatarData = data
            runGeneration { await generator.generate(photoData: data, into: friend) }
        }
    }

    private func runGeneration(_ work: @escaping () async -> Void) {
        Task {
            isRegenerating = true
            await work()
            isRegenerating = false
        }
    }
}
