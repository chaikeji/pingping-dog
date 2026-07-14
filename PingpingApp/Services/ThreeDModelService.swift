import Foundation

struct ThreeDModelStatus {
    var status: ModelBuildStatus
    var modelURL: URL?
}

protocol ThreeDModelServicing {
    func submitCapture(imageData: [Data]) async throws -> String
    func pollStatus(jobID: String) async throws -> ThreeDModelStatus
}

// 占位实现：等 3D 建模 API 的 endpoint / 鉴权方式 / 输入格式确认后替换为真实网络请求。
struct PlaceholderThreeDModelService: ThreeDModelServicing {
    func submitCapture(imageData: [Data]) async throws -> String {
        UUID().uuidString
    }

    func pollStatus(jobID: String) async throws -> ThreeDModelStatus {
        ThreeDModelStatus(status: .processing, modelURL: nil)
    }
}
