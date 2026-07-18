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
                    Button {
                        previewURL = friend.model3DLocalURL
                    } label: {
                        Label("查看 3D 模型", systemImage: "cube.transparent")
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

                // 不满意/失败了都能换张照片重新生成，不用删掉朋友重建。
                if isRegenerating {
                    HStack {
                        ProgressView()
                        Text("重新生成中…")
                    }
                } else if friend.modelStatus == .ready || friend.modelStatus == .failed {
                    Button(friend.modelStatus == .failed ? "换张照片重试" : "不满意？换张照片重新生成") {
                        showPhotoOptions = true
                    }
                }
            }
        }
        .navigationTitle(friend.name)
        .quickLookPreview($previewURL)
        .photoSourcePicker(isPresented: $showPhotoOptions) { data in
            friend.avatarData = data
            Task {
                isRegenerating = true
                await generator.generate(photoData: data, into: friend)
                isRegenerating = false
            }
        }
    }
}
