import Foundation

struct ThreeDModelStatus {
    var status: ModelBuildStatus
    var modelURL: URL?
}

struct RigCheckResult {
    var riggable: Bool
    var rigType: String?
}

protocol ThreeDModelServicing {
    func submitCapture(imageData: [Data]) async throws -> String
    func pollStatus(jobID: String) async throws -> ThreeDModelStatus
    func convert(taskID: String, format: String) async throws -> String
    func checkRiggable(taskID: String) async throws -> RigCheckResult
    func rig(taskID: String, rigType: String, rigModel: String) async throws -> String
    func retarget(taskID: String, animation: String, animateInPlace: Bool) async throws -> String
}

enum TripoServiceError: Error {
    case missingAPIKey
    case unsupportedImageFormat
    case unexpectedResponse
    case taskFailed(String)
    /// Tripo 统一错误响应：{"code": 2010, "message": "Insufficient credits", "suggestion": "..."}
    case apiError(code: Int, message: String, suggestion: String?)
    /// App 自己判断出的失败原因（不是 Tripo 接口返回的），比如"这张照片没法绑骨"。
    case custom(String)

    /// 给 UI 展示用的人话文案。
    var displayMessage: String {
        switch self {
        case .missingAPIKey: return "没有配置 Tripo API Key"
        case .custom(let message): return message
        case .unsupportedImageFormat: return "图片格式不支持（只支持 JPEG / PNG）"
        case .unexpectedResponse: return "接口返回的数据对不上，可能是 Tripo 那边改了格式"
        case .taskFailed(let status): return "生成任务失败（状态：\(status)）"
        case .apiError(let code, let message, let suggestion):
            var text = "Tripo 报错（\(code)）：\(message)"
            if let suggestion { text += "，\(suggestion)" }
            return text
        }
    }
}

/// 接 Tripo3D (https://developers.tripo3d.ai) 的 image-to-model API。
/// 流程：POST /files 上传图片换 file_token → POST /generation/image-to-model 提交生成任务 → GET /tasks/{id} 轮询。
struct TripoThreeDModelService: ThreeDModelServicing {
    private let baseURL = URL(string: "https://openapi.tripo3d.ai/v3")!
    private let modelVersion = "v3.1-20260211"

    private var apiKey: String {
        get throws {
            guard let key = Bundle.main.object(forInfoDictionaryKey: "TripoAPIKey") as? String,
                  !key.isEmpty, key != "your_api_key_here" else {
                throw TripoServiceError.missingAPIKey
            }
            return key
        }
    }

    // MARK: - 上传图片换 file_token

    private func uploadImage(_ data: Data) async throws -> String {
        let (fileExtension, mimeType) = try Self.detectImageType(data)
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        body.append("--\(boundary)\r\n".utf8)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(fileExtension)\"\r\n".utf8)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".utf8)

        var request = URLRequest(url: baseURL.appending(path: "files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, _) = try await URLSession.shared.data(for: request)
        let payload = try Self.unwrap(responseData)
        guard let fileToken = payload["file_token"] as? String else { throw TripoServiceError.unexpectedResponse }
        return fileToken
    }

    /// 只支持 Tripo 允许的 JPEG / PNG，通过文件头 magic bytes 判断，不依赖调用方传入的扩展名。
    private static func detectImageType(_ data: Data) throws -> (fileExtension: String, mimeType: String) {
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if data.starts(with: pngMagic) { return ("png", "image/png") }
        if data.count > 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xD8 {
            return ("jpg", "image/jpeg")
        }
        throw TripoServiceError.unsupportedImageFormat
    }

    // MARK: - 生成任务

    func submitCapture(imageData: [Data]) async throws -> String {
        guard let firstImage = imageData.first else { throw TripoServiceError.unexpectedResponse }
        let fileToken = try await uploadImage(firstImage)

        var request = URLRequest(url: baseURL.appending(path: "generation/image-to-model"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "file_token": fileToken,
            "model": modelVersion,
            "texture": true,
            "pbr": true,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseTaskID(from: data)
    }

    // MARK: - 轮询状态

    func pollStatus(jobID: String) async throws -> ThreeDModelStatus {
        var request = URLRequest(url: baseURL.appending(path: "tasks/\(jobID)"))
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let task = try Self.unwrap(data)
        guard let status = task["status"] as? String else { throw TripoServiceError.unexpectedResponse }

        switch status {
        case "success":
            let output = task["output"] as? [String: Any]
            let urlString = output?["model_url"] as? String
            return ThreeDModelStatus(status: .ready, modelURL: urlString.flatMap(URL.init(string:)))
        case "failed", "cancelled", "banned":
            throw TripoServiceError.taskFailed(status)
        default:
            return ThreeDModelStatus(status: .processing, modelURL: nil)
        }
    }

    // MARK: - 转格式（GLB → USDZ，供 QuickLook/RealityKit 原生展示）

    func convert(taskID: String, format: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "models/convert"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": taskID,
            "format": format,
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseTaskID(from: data)
    }

    // MARK: - 骨骼绑定 + 动作重定向（首页"会走路的平平"用）
    // 链路：rig-check（能不能绑骨、推荐哪种骨骼类型）→ rig（绑骨，四足要用 v2.5 模型）→
    // retarget（套 preset:quadruped:walk 这个预设动作，animate_in_place 让它原地走不产生位移）。

    func checkRiggable(taskID: String) async throws -> RigCheckResult {
        var request = URLRequest(url: baseURL.appending(path: "animations/rig-check"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": taskID])

        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try Self.unwrap(data)
        return RigCheckResult(riggable: payload["riggable"] as? Bool ?? false, rigType: payload["rig_type"] as? String)
    }

    /// - Parameter rigModel: 绑骨模型版本。`v1.0-20240301` 只支持双足，四足/其他非人形要用 `v2.5-20260210`。
    func rig(taskID: String, rigType: String, rigModel: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "animations/rig"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": taskID,
            "model": rigModel,
            "rig_type": rigType,
            "spec": "tripo",
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseTaskID(from: data)
    }

    func retarget(taskID: String, animation: String, animateInPlace: Bool) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "animations/retarget"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "input": taskID,
            "animation": animation,
            "animate_in_place": animateInPlace,
            "out_format": "glb",
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseTaskID(from: data)
    }

    private static func parseTaskID(from data: Data) throws -> String {
        let payload = try unwrap(data)
        guard let taskID = payload["task_id"] as? String else { throw TripoServiceError.unexpectedResponse }
        return taskID
    }

    /// 统一响应格式：{"code": 0, "data": {...}} 表示成功；code 非 0 时是
    /// {"code": 2010, "message": "...", "suggestion": "..."} 这种错误形状。
    /// 先看 code，别一上来就假设有 "data"，不然余额不足这类错误只会变成一个语焉不详的 unexpectedResponse。
    private static func unwrap(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TripoServiceError.unexpectedResponse
        }
        let code = json["code"] as? Int ?? 0
        if code != 0 {
            let message = json["message"] as? String ?? "未知错误"
            let suggestion = json["suggestion"] as? String
            throw TripoServiceError.apiError(code: code, message: message, suggestion: suggestion)
        }
        guard let payload = json["data"] as? [String: Any] else { throw TripoServiceError.unexpectedResponse }
        return payload
    }
}

// 占位实现：本地开发/预览时用，不发真实网络请求。
struct PlaceholderThreeDModelService: ThreeDModelServicing {
    func submitCapture(imageData: [Data]) async throws -> String {
        UUID().uuidString
    }

    func pollStatus(jobID: String) async throws -> ThreeDModelStatus {
        ThreeDModelStatus(status: .processing, modelURL: nil)
    }

    func convert(taskID: String, format: String) async throws -> String {
        UUID().uuidString
    }

    func checkRiggable(taskID: String) async throws -> RigCheckResult {
        RigCheckResult(riggable: true, rigType: "quadruped")
    }

    func rig(taskID: String, rigType: String, rigModel: String) async throws -> String {
        UUID().uuidString
    }

    func retarget(taskID: String, animation: String, animateInPlace: Bool) async throws -> String {
        UUID().uuidString
    }
}
