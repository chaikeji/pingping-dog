import SwiftUI
import PhotosUI
import QuickLook

struct FriendDetailView: View {
    @Bindable var friend: DogFriend
    @State private var previewURL: URL?
    @State private var regeneratePickerItem: PhotosPickerItem?
    @State private var isRegenerating = false

    private let generator = ThreeDModelGenerator(modelService: TripoThreeDModelService())

    var body: some View {
        Form {
            if let data = friend.photoData, let uiImage = UIImage(data: data) {
                Section {
                    Image(uiImage: uiImage).resizable().scaledToFit()
                }
            }
            Section("信息") {
                LabeledContent("名字", value: friend.name)
                LabeledContent("品种", value: friend.breed)
                LabeledContent("主人", value: friend.ownerName)
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
                    PhotosPicker(
                        friend.modelStatus == .failed ? "换张照片重试" : "不满意？换张照片重新生成",
                        selection: $regeneratePickerItem,
                        matching: .images
                    )
                }
            }
        }
        .navigationTitle(friend.name)
        .quickLookPreview($previewURL)
        .task(id: regeneratePickerItem) {
            guard let regeneratePickerItem, let rawData = try? await regeneratePickerItem.loadTransferable(type: Data.self) else { return }
            guard let uiImage = UIImage(data: rawData), let jpegData = uiImage.jpegData(compressionQuality: 0.9) else { return }

            friend.photoData = jpegData
            isRegenerating = true
            await generator.generate(photoData: jpegData, into: friend)
            isRegenerating = false
            self.regeneratePickerItem = nil
        }
    }
}
