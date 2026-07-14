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

    init(name: String = "平平", breed: String = "", birthday: Date? = nil, avatarData: Data? = nil, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.breed = breed
        self.birthday = birthday
        self.avatarData = avatarData
        self.ownerID = ownerID
        self.createdAt = .now
    }
}
