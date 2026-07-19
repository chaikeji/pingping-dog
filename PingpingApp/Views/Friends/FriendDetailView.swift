import SwiftUI
import PhotosUI
import QuickLook

struct FriendDetailView: View {
    @Bindable var friend: DogFriend
    @State private var previewURL: URL?
    @State private var showPhotoOptions = false
    @State private var isRegenerating = false

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())

    var body: some View {
        Form {
            if let data = friend.avatarData, let uiImage = UIImage(data: data) {
                Section {
                    Image(uiImage: uiImage).resizable().scaledToFit()
                }
            }
            Section("信息") {
                LabeledContent("名字", value: friend.name)
                if !friend.gender.isEmpty { LabeledContent("性别", value: friend.gender) }
                if !friend.ageText.isEmpty { LabeledContent("年龄", value: friend.ageText) }
                LabeledContent("认识日期", value: friend.metDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("亲密度", value: "\(friend.intimacy)")
            }
            Section("3D 模型") {
                switch friend.modelStatus {
                case .ready:
                    // 按当前容器解析，重装后旧的绝对路径不能直接用。解析不到说明文件没了。
                    if let modelURL = ModelStorage.resolve(friend.model3DLocalURL) {
                        Button {
                            previewURL = modelURL
                        } label: {
                            Label("查看 3D 模型", systemImage: "cube.transparent")
                        }
                    } else {
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
