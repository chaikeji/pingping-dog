import Foundation

/// 拍照 → 3D 模型的完整流程，供「认识新朋友」首次生成和「换照片重新生成」复用（仅狗朋友）。
struct ThreeDModelGenerator {
    let modelService: ThreeDModelServicing

    /// 生成（GLB）→ 转 USDZ，给 QuickLook 用。
    /// 失败重试时会从「服务端已经跑到哪一步」接着做，而不是从头再来一遍。
    /// 生成一次要 30 额度、转换 5 额度，而最容易断的恰恰是最后下载那 50 多 MB；
    /// 从头重跑等于为一次网络抖动再付一次全款。
    func generate(photoData: Data, into holder: Model3DHolder) async {
        holder.modelErrorMessage = nil
        do {
            holder.modelStatus = .processing

            // 第 1 步：生成。已有任务且服务端已成功就直接复用。
            let jobID: String
            if let existing = holder.model3DRemoteJobID, await isFinished(jobID: existing) {
                jobID = existing
            } else {
                holder.modelStatus = .queued
                jobID = try await modelService.submitCapture(imageData: [photoData])
                holder.model3DRemoteJobID = jobID
                holder.model3DConvertJobID = nil   // 换了新的生成任务，旧的转换结果就作废了
                holder.modelStatus = .processing
                _ = try await waitForCompletion(jobID: jobID)
            }

            // 第 2 步：转 USDZ。同样能复用。
            let convertJobID: String
            if let existing = holder.model3DConvertJobID, await isFinished(jobID: existing) {
                convertJobID = existing
            } else {
                convertJobID = try await modelService.convert(taskID: jobID, format: "USDZ")
                holder.model3DConvertJobID = convertJobID
            }
            let convertResult = try await waitForCompletion(jobID: convertJobID)
            guard let usdzURL = convertResult.modelURL else { throw TripoServiceError.unexpectedResponse }

            // 第 3 步：下载。到这里额度已经花完了，所以这步值得多试几次。
            holder.model3DLocalURL = try await downloadModel(from: usdzURL, ownerID: holder.id)
            holder.modelStatus = .ready
        } catch {
            holder.modelStatus = .failed
            holder.modelErrorMessage = Self.message(for: error)
        }
    }

    /// 服务端这个任务是不是已经成功了。查不到 / 失败 / 还在跑都算「不能复用」，
    /// 出错时返回 false 让调用方走正常重跑，不要因为查状态失败就中断整个流程。
    private func isFinished(jobID: String) async -> Bool {
        ((try? await modelService.pollStatus(jobID: jobID))?.status == .ready)
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

    /// 每 3 秒查一次，最多等 10 分钟。
    /// 别把上限调回 3 分钟：实测一次普通生成就要约 2.5 分钟，3 分钟几乎贴着天花板，
    /// 稍微慢一点就会在服务端明明会成功的情况下被判超时，白扣一次额度。
    private func waitForCompletion(jobID: String) async throws -> ThreeDModelStatus {
        for _ in 0..<200 {
            let result = try await modelService.pollStatus(jobID: jobID)
            if result.status == .ready { return result }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw TripoServiceError.taskFailed("timeout")
    }

    /// USDZ 有 50 MB 以上，走代理下载中途断开是常事（表现为 networkConnectionLost）。
    /// 这步之前的额度已经花掉了，断一次就重来一整轮太亏，所以这里自己重试三次。
    private func downloadModel(from remoteURL: URL, ownerID: UUID) async throws -> URL {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try await attemptDownload(from: remoteURL, ownerID: ownerID)
            } catch {
                lastError = error
                // 取消是用户/系统主动中断，重试没有意义。
                if (error as? URLError)?.code == .cancelled { throw error }
                if attempt < 3 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
        throw lastError ?? TripoServiceError.unexpectedResponse
    }

    private func attemptDownload(from remoteURL: URL, ownerID: UUID) async throws -> URL {
        // 同样走放宽超时的 session：USDZ 有几十 MB，默认 60 秒在国内网络也可能不够。
        let (tempURL, _) = try await TripoThreeDModelService.session.download(from: remoteURL)
        let destination = try ModelStorage.destination(ownerID: ownerID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
