import SwiftUI
import PhotosUI

struct AddFriendView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var breed = ""
    @State private var ownerName = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?

    private let modelService: ThreeDModelServicing = PlaceholderThreeDModelService()

    var body: some View {
        NavigationStack {
            Form {
                TextField("狗狗名字", text: $name)
                TextField("品种", text: $breed)
                TextField("主人称呼", text: $ownerName)
                PhotosPicker("选择照片（用于生成3D模型）", selection: $pickerItem, matching: .images)
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage).resizable().scaledToFit().frame(height: 160)
                }
            }
            .navigationTitle("认识新朋友")
            .toolbar {
                Button("保存") { save() }.disabled(name.isEmpty)
            }
            .task(id: pickerItem) {
                if let pickerItem, let data = try? await pickerItem.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    private func save() {
        let friend = DogFriend(name: name, breed: breed, ownerName: ownerName, photoData: photoData)
        context.insert(friend)
        dismiss()

        guard let photoData else { return }
        friend.modelStatus = .queued
        Task {
            do {
                let jobID = try await modelService.submitCapture(imageData: [photoData])
                friend.model3DRemoteJobID = jobID
                friend.modelStatus = .processing
            } catch {
                friend.modelStatus = .failed
            }
        }
    }
}
