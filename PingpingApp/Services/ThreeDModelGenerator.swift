import Foundation

/// 拍照 → 3D 模型的完整流程，供「认识新朋友」首次生成和「换照片重新生成」复用（仅狗朋友）。
struct ThreeDModelGenerator {
    let modelService: ThreeDModelServicing

    /// 生成（GLB）→ 转 USDZ，给 QuickLook 用。
    /// 每段各自轮询，每 3 秒查一次，最多等 3 分钟，超时按失败处理。
    func generate(photoData: Data, into holder: Model3DHolder) async {
        holder.modelErrorMessage = nil
        holder.modelStatus = .queued
        do {
            let jobID = try await modelService.submitCapture(imageData: [photoData])
            holder.model3DRemoteJobID = jobID
            holder.modelStatus = .processing

            _ = try await waitForCompletion(jobID: jobID)
            let convertJobID = try await modelService.convert(taskID: jobID, format: "USDZ")
            let convertResult = try await waitForCompletion(jobID: convertJobID)
            guard let usdzURL = convertResult.modelURL else { throw TripoServiceError.unexpectedResponse }

            holder.model3DLocalURL = try await downloadModel(from: usdzURL, ownerID: holder.id)
            holder.modelStatus = .ready
        } catch {
            holder.modelStatus = .failed
            holder.modelErrorMessage = (error as? TripoServiceError)?.displayMessage ?? error.localizedDescription
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

    private func downloadModel(from remoteURL: URL, ownerID: UUID) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
        let destination = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(ownerID.uuidString).usdz")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
