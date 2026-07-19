import Foundation

struct ThreeDModelStatus {
    var status: ModelBuildStatus
    var modelURL: URL?
}

protocol ThreeDModelServicing {
    func submitCapture(imageData: [Data]) async throws -> String
    func pollStatus(jobID: String) async throws -> ThreeDModelStatus
    func convert(taskID: String, format: String) async throws -> String
}

enum TripoServiceError: Error {
    case missingAPIKey
    case unsupportedImageFormat
    case unexpectedResponse
    case taskFailed(String)
    /// Tripo 统一错误响应：{"code": 2010, "message": "Insufficient credits", "suggestion": "..."}
    case apiError(code: Int, message: String, suggestion: String?)

    /// 给 UI 展示用的人话文案。
    var displayMessage: String {
        switch self {
        case .missingAPIKey: return "没有配置 Tripo API Key"
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

/// 接 Tripo3D (https://developers.tripo3d.ai) 的 image-to-model API，只用于「狗朋友」。
/// 流程：POST /files 上传图片换 file_token → POST /generation/image-to-model 提交任务 → GET /tasks/{id} 轮询 → POST /models/convert 转 USDZ。
/// （平平本人 3D 改为自备 USDZ 导入，不走此链路，故不再有绑骨 / retarget。）
struct TripoThreeDModelService: ThreeDModelServicing {
    /// Tripo API 入口，必须是 .ai。
    /// .com 是解析到国内节点的另一套部署，账号体系独立：platform.tripo3d.ai 上申请的 key
    /// 拿到 .com 去会被直接判 `{"code":2,"message":"Invalid API key"}`。
    /// 两个域名在国内都连得通，所以别再因为「国内网络」把它换成 .com。
    private let baseURL = URL(string: "https://openapi.tripo3d.ai/v3")!
    private let modelVersion = "v3.1-20260211"

    /// 不用 URLSession.shared：它默认 60 秒请求超时，国内移动网络传图片很容易在中途卡够 60 秒，
    /// 报出来就是那句 "The request timed out"。这里给上传留足时间，并允许等蜂窝网络恢复。
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120   // 单次请求两次数据之间的最长空档
        config.timeoutIntervalForResource = 600  // 整个传输的总上限
        config.waitsForConnectivity = true       // 暂时没网时先等，而不是立刻失败
        return URLSession(configuration: config)
    }()

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

    /// 返回 file_token 和图片类型：提交任务时 `file.type` 必须跟着一起传，所以这里不能只回 token。
    private func uploadImage(_ data: Data) async throws -> (token: String, type: String) {
        let (fileExtension, mimeType) = try Self.detectImageType(data)
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(fileExtension)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appending(path: "files"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, _) = try await Self.session.data(for: request)
        let payload = try Self.unwrap(responseData)
        guard let fileToken = payload["file_token"] as? String else { throw TripoServiceError.unexpectedResponse }
        return (fileToken, fileExtension)
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
        let uploaded = try await uploadImage(firstImage)

        var request = URLRequest(url: baseURL.appending(path: "generation/image-to-model"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 图片要包在 file 对象里（{"type": "jpg", "file_token": "..."}）。
        // 平铺成顶层的 "file_token" 会被判 1004 "file is required for image_to_model"。
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelVersion,
            "file": [
                "type": uploaded.type,
                "file_token": uploaded.token,
            ],
            "texture": true,
            "pbr": true,
        ])

        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseTaskID(from: data)
    }

    // MARK: - 轮询状态

    func pollStatus(jobID: String) async throws -> ThreeDModelStatus {
        var request = URLRequest(url: baseURL.appending(path: "tasks/\(jobID)"))
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await Self.session.data(for: request)
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

        let (data, _) = try await Self.session.data(for: request)
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
}
