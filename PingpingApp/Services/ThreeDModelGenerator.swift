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
            holder.modelErrorMessage = Self.message(for: error)
        }
    }

    /// 网络类错误的 localizedDescription 是英文系统文案（比如 "The request timed out"），
    /// 直接甩给用户既看不懂也不知道该干嘛，这里换成中文并给出下一步。
    private static func message(for error: Error) -> String {
        if let tripoError = error as? TripoServiceError { return tripoError.displayMessage }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "网络超时了，照片没传完。换个网络（Wi-Fi 通常更稳）再试一次"
        case NSURLErrorNotConnectedToInternet:
            return "现在没有网络连接"
        case NSURLErrorNetworkConnectionLost:
            return "传到一半断网了，再试一次"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "连不上 Tripo 服务器，可能是网络受限"
        default:
            return "网络出错了（\(nsError.code)）：\(nsError.localizedDescription)"
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
        // 同样走放宽超时的 session：USDZ 有几 MB，默认 60 秒在国内网络也可能不够。
        let (tempURL, _) = try await TripoThreeDModelService.session.download(from: remoteURL)
        let destination = try ModelStorage.destination(ownerID: ownerID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
