import Foundation
import SwiftData

@Model
final class DogProfile {
    var id: UUID
    var name: String
    var breed: String
    var birthday: Date?
    var avatarData: Data?
    var ownerID: String?
    var createdAt: Date

    /// 首页"会走路的平平"，用 avatarData 生成一次、缓存本地，之后不再重复调用 API。
    var model3DLocalURL: URL?
    var model3DRemoteJobID: String?
    var modelStatus: ModelBuildStatus
    var modelErrorMessage: String?

    init(name: String = "平平", breed: String = "", birthday: Date? = nil, avatarData: Data? = nil, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.breed = breed
        self.birthday = birthday
        self.avatarData = avatarData
        self.ownerID = ownerID
        self.createdAt = .now
        self.modelStatus = .notStarted
    }
}

extension DogProfile: Model3DHolder {}
