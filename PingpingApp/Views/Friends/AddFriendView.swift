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

    private let modelService: ThreeDModelServicing = TripoThreeDModelService()

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
                guard let pickerItem, let rawData = try? await pickerItem.loadTransferable(type: Data.self) else { return }
                // 系统相册原图常是 HEIC，Tripo 只收 JPEG/PNG，这里统一转成 JPEG 再往下用。
                if let uiImage = UIImage(data: rawData), let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                    photoData = jpegData
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
                try await pollUntilDone(jobID: jobID, friend: friend)
            } catch {
                friend.modelStatus = .failed
            }
        }
    }

    /// 建模是两段异步任务：先生成模型（GLB），再转成 USDZ 给 QuickLook/RealityKit 用。
    /// 每段各自轮询，每 3 秒查一次，最多等 3 分钟，超时按失败处理。
    private func pollUntilDone(jobID: String, friend: DogFriend) async throws {
        _ = try await waitForCompletion(jobID: jobID)

        let convertJobID = try await modelService.convert(taskID: jobID, format: "USDZ")
        let convertResult = try await waitForCompletion(jobID: convertJobID)
        guard let usdzURL = convertResult.modelURL else { throw TripoServiceError.unexpectedResponse }

        friend.model3DLocalURL = try await downloadModel(from: usdzURL, friendID: friend.id)
        friend.modelStatus = .ready
    }

    private func waitForCompletion(jobID: String) async throws -> ThreeDModelStatus {
        for _ in 0..<60 {
            let result = try await modelService.pollStatus(jobID: jobID)
            if result.status == .ready { return result }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw TripoServiceError.taskFailed("timeout")
    }

    private func downloadModel(from remoteURL: URL, friendID: UUID) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let destination = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(friendID.uuidString).usdz")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
