import Foundation
import SwiftData

enum ModelBuildStatus: String, Codable {
    case notStarted, queued, processing, ready, failed
}

/// 3D 建模的公共字段，`DogProfile`（平平自己）和 `DogFriend`（狗朋友）都实现这个协议，
/// 这样 `ThreeDModelGenerator` 可以复用同一套生成/绑骨/动画逻辑，不用为两个 model 各写一份。
protocol Model3DHolder: AnyObject {
    var id: UUID { get }
    var model3DLocalURL: URL? { get set }
    var model3DRemoteJobID: String? { get set }
    var modelStatus: ModelBuildStatus { get set }
    var modelErrorMessage: String? { get set }
}

@Model
final class DogFriend {
    var id: UUID
    var name: String
    var breed: String
    var ownerName: String
    var photoData: Data?
    var model3DLocalURL: URL?
    var model3DRemoteJobID: String?
    var modelStatus: ModelBuildStatus
    var modelErrorMessage: String?
    var ownerID: String?
    var createdAt: Date

    init(name: String, breed: String = "", ownerName: String = "", photoData: Data? = nil, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.breed = breed
        self.ownerName = ownerName
        self.photoData = photoData
        self.modelStatus = .notStarted
        self.ownerID = ownerID
        self.createdAt = .now
    }
}

extension DogFriend: Model3DHolder {}
