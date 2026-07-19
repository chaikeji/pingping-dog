import Foundation

/// 拍照 → 3D 模型的完整流程，供「认识新朋友」首次生成和「换照片重新生成」复用（仅狗朋友）。
struct ThreeDModelGenerator {
    let modelService: ThreeDModelServicing

    /// 用新照片生成。旧任务是按旧照片跑的，所以一律重新提交，不能复用 —— 否则换照片等于没换。
    func generate(photoData: Data, into holder: Model3DHolder) async {
        await run(photoData: photoData, into: holder, reusingExistingJobs: false)
    }

    /// 用同一张照片重试（典型场景：服务端都跑完了，只是最后下载断了）。
    /// 服务端已完成的步骤直接复用：生成 30 额度、转换 5 额度，能省则省。
    ///
    /// 注意有个约 24 小时的窗口：Tripo 的 model_url 是带签名且有效期固定的，
    /// 重新查询任务返回的是同一条 URL、不会续期（实测连查两次 URL 完全一致）。
    /// 所以超过一天再重试，复用转换任务这步会因为链接失效而下载不下来，
    /// 只能重新转换（5 额度）。这是接口特性、不是 bug，别照着「重试怎么又扣钱了」去查。
    func retry(photoData: Data, into holder: Model3DHolder) async {
        await run(photoData: photoData, into: holder, reusingExistingJobs: true)
    }

    /// 生成（GLB）→ 转 USDZ，给 QuickLook 用。
    private func run(photoData: Data, into holder: Model3DHolder, reusingExistingJobs: Bool) async {
        holder.modelErrorMessage = nil
        do {
            holder.modelStatus = .processing

            // 第 1 步：生成。重试时若服务端那条任务已成功，直接复用。
            //
            // 这里绝不能「查不到就当没有、重新交一单」：重交一次是 30 额度，
            // 而查状态失败最常见的原因只是网络抖了一下。宁可报错让用户自己决定，
            // 也不能替他花钱 —— 之前就是这么把用户的 30 额度花掉的。
            let jobID: String
            if reusingExistingJobs, let existing = holder.model3DRemoteJobID {
                // 故意不用 try?：网络错误要原样抛出去，让用户看到「断网了，再试一次」而不是被扣钱。
                let status = try await modelService.pollStatus(jobID: existing)
                guard status.status == .ready else { throw TripoServiceError.cannotResume }
                jobID = existing
            } else {
                holder.modelStatus = .queued
                jobID = try await modelService.submitCapture(imageData: [photoData])
                holder.model3DRemoteJobID = jobID
                holder.model3DConvertJobID = nil   // 换了新的生成任务，旧的转换结果就作废了
                holder.modelStatus = .processing
                _ = try await waitForCompletion(jobID: jobID)
            }

            // 第 2 步：转 USDZ。同样能复用（第 1 步若重新提交过，上面已把它清成 nil）。
            // 转换只要 5 额度，但道理一样：查状态失败就抛错，别默默再交一单。
            var reusableConvertJobID: String?
            if let existing = holder.model3DConvertJobID {
                let status = try await modelService.pollStatus(jobID: existing)
                if status.status == .ready { reusableConvertJobID = existing }
            }

            let convertJobID: String
            if let reusableConvertJobID {
                convertJobID = reusableConvertJobID
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
        ModelThumbnail.invalidate(ownerID: ownerID)   // 换了模型，列表缩略图要重新渲染
        return destination
    }
}
