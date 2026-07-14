import Foundation
import SwiftData

enum ModelBuildStatus: String, Codable {
    case notStarted, queued, processing, ready, failed
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
