import Foundation

/// 拍照 → 3D 模型的完整流程，供"认识新朋友"首次生成、"重新生成"、以及首页"会走路的平平"复用。
struct ThreeDModelGenerator {
    let modelService: ThreeDModelServicing

    /// 静态模型：生成（GLB）→ 转 USDZ，给 QuickLook 用。
    /// 每段各自轮询，每 3 秒查一次，最多等 3 分钟，超时按失败处理。
    func generate(photoData: Data, into holder: Model3DHolder) async {
        await run(photoData: photoData, into: holder) { jobID in
            let convertJobID = try await modelService.convert(taskID: jobID, format: "USDZ")
            let convertResult = try await waitForCompletion(jobID: convertJobID)
            guard let usdzURL = convertResult.modelURL else { throw TripoServiceError.unexpectedResponse }
            return usdzURL
        }
    }

    /// 会走路的模型：生成 → rig-check → 绑骨 → 套 preset 动作原地循环 → 转 USDZ。
    /// 比静态模型多两段异步任务，会多消耗积分和等待时间，只在用户主动点"生成会走路的平平"时调用一次。
    func generateWalkingLoop(photoData: Data, into holder: Model3DHolder) async {
        await run(photoData: photoData, into: holder) { jobID in
            let check = try await modelService.checkRiggable(taskID: jobID)
            guard check.riggable else {
                throw TripoServiceError.custom("这张照片生成的模型没法绑骨，换一张轮廓更清晰、姿势自然的照片试试")
            }
            let rigType = check.rigType ?? "quadruped"
            let rigModel = rigType == "biped" ? "v1.0-20240301" : "v2.5-20260210"

            let rigJobID = try await modelService.rig(taskID: jobID, rigType: rigType, rigModel: rigModel)
            _ = try await waitForCompletion(jobID: rigJobID)

            let retargetJobID = try await modelService.retarget(
                taskID: rigJobID,
                animation: Self.walkPreset(for: rigType),
                animateInPlace: true
            )
            _ = try await waitForCompletion(jobID: retargetJobID)

            let convertJobID = try await modelService.convert(taskID: retargetJobID, format: "USDZ")
            let convertResult = try await waitForCompletion(jobID: convertJobID)
            guard let usdzURL = convertResult.modelURL else { throw TripoServiceError.unexpectedResponse }
            return usdzURL
        }
    }

    /// 共用骨架：提交生成任务 → 等它完成 → 跑调用方给的后续步骤（拿到最终 USDZ 直链）→ 下载存本地。
    private func run(photoData: Data, into holder: Model3DHolder, finalStage: (String) async throws -> URL) async {
        holder.modelErrorMessage = nil
        holder.modelStatus = .queued
        do {
            let jobID = try await modelService.submitCapture(imageData: [photoData])
            holder.model3DRemoteJobID = jobID
            holder.modelStatus = .processing

            _ = try await waitForCompletion(jobID: jobID)
            let usdzURL = try await finalStage(jobID)

            holder.model3DLocalURL = try await downloadModel(from: usdzURL, ownerID: holder.id)
            holder.modelStatus = .ready
        } catch {
            holder.modelStatus = .failed
            holder.modelErrorMessage = (error as? TripoServiceError)?.displayMessage ?? error.localizedDescription
        }
    }

    private static func walkPreset(for rigType: String) -> String {
        switch rigType {
        case "biped": return "preset:walk"
        case "hexapod": return "preset:hexapod:walk"
        case "octopod": return "preset:octopod:walk"
        case "serpentine": return "preset:serpentine:march"
        case "aquatic": return "preset:aquatic:march"
        default: return "preset:quadruped:walk"
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
