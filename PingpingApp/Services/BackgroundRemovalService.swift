import Foundation
import UIKit

enum BackgroundRemovalError: Error {
    case missingAPIKey
    case placeholderAPIKey
    case badResponse(status: Int, body: String)
    case emptyResponse

    var displayMessage: String {
        switch self {
        case .missingAPIKey: return "没有配置 remove.bg API Key"
        case .placeholderAPIKey: return "remove.bg key 还是占位值，改 Config/Secrets.xcconfig"
        case .badResponse(let s, let b): return "remove.bg 报错（HTTP \(s)）：\(b.prefix(200))"
        case .emptyResponse: return "remove.bg 回了空 body"
        }
    }
}

/// remove.bg 抠图 API 客户端。文档：https://www.remove.bg/api
///
/// 遛狗贴纸默认用 preview；好友 3D 建模显式用 auto，让接口按原图返回可用的高分辨率结果。
/// type=animal 让服务端知道主体是动物，狗绳 / 环境的分割会更干净。
/// 我们的原图是 [[WalkSessionViewModel]] 存下来的 JPEG，POST multipart 直接怼过去就行。
struct BackgroundRemovalService {

    enum OutputSize: String {
        case preview
        case automatic = "auto"
    }

    private let endpoint = URL(string: "https://api.remove.bg/v1.0/removebg")!

    /// 单独一个 URLSession：抠图接口在国内往往要跑十几秒，别拿默认 60 秒超时挤同一个池子。
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private var apiKey: String {
        get throws {
            guard let key = Bundle.main.object(forInfoDictionaryKey: "RemoveBgAPIKey") as? String,
                  !key.isEmpty else {
                throw BackgroundRemovalError.missingAPIKey
            }
            // CI build 会写入 ci_placeholder，例子文件里是 your_removebg_api_key_here。
            // 两个都拦下来避免真机上把假 key 打过去被 remove.bg 计一次失败调用。
            if key == "ci_placeholder" || key == "your_removebg_api_key_here" {
                throw BackgroundRemovalError.placeholderAPIKey
            }
            return key
        }
    }

    /// 把一张 JPEG 抠成透明背景 PNG。返回 PNG data（带 alpha 通道）。
    func removeBackground(imageData: Data, size: OutputSize = .preview) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // multipart 三块参数：image_file / size / type / format。
        // - size：贴纸传 preview；3D 建模按官方推荐传 auto。
        // - type=animal：告诉引擎主体是动物，比默认 auto 好一点，尤其是狗绳的处理。
        // - format=png：拿透明通道。
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        appendField("size", size.rawValue)
        appendField("type", "animal")
        appendField("format", "png")

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image_file\"; filename=\"photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(try apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackgroundRemovalError.emptyResponse
        }
        // 200 = image bytes；402 = 额度用完；429 = rate limit；其它一律报出来。
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw BackgroundRemovalError.badResponse(status: http.statusCode, body: bodyText)
        }
        guard !data.isEmpty else { throw BackgroundRemovalError.emptyResponse }
        return data
    }
}
