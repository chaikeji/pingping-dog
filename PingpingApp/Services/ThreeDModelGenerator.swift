import Foundation

/// 拍照 → 3D 模型的完整流程，供"认识新朋友"首次生成和"重新生成"复用。
struct ThreeDModelGenerator {
    let modelService: ThreeDModelServicing

    /// 建模是两段异步任务：先生成模型（GLB），再转成 USDZ 给 QuickLook/RealityKit 用。
    /// 每段各自轮询，每 3 秒查一次，最多等 3 分钟，超时按失败处理。
    func generate(photoData: Data, into friend: DogFriend) async {
        friend.modelErrorMessage = nil
        friend.modelStatus = .queued
        do {
            let jobID = try await modelService.submitCapture(imageData: [photoData])
            friend.model3DRemoteJobID = jobID
            friend.modelStatus = .processing

            _ = try await waitForCompletion(jobID: jobID)
            let convertJobID = try await modelService.convert(taskID: jobID, format: "USDZ")
            let convertResult = try await waitForCompletion(jobID: convertJobID)
            guard let usdzURL = convertResult.modelURL else { throw TripoServiceError.unexpectedResponse }

            friend.model3DLocalURL = try await downloadModel(from: usdzURL, friendID: friend.id)
            friend.modelStatus = .ready
        } catch {
            friend.modelStatus = .failed
            friend.modelErrorMessage = (error as? TripoServiceError)?.displayMessage ?? error.localizedDescription
        }
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
