import SwiftUI
import QuickLook

struct FriendDetailView: View {
    @Bindable var friend: DogFriend
    @State private var previewURL: URL?

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
                case .processing, .queued: Label("生成中…", systemImage: "hourglass")
                case .failed: Label("生成失败，可重试", systemImage: "exclamationmark.triangle")
                case .notStarted: Text("未提交建模")
                }
            }
        }
        .navigationTitle(friend.name)
        .quickLookPreview($previewURL)
    }
}
