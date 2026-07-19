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

    /// 平平首页的 3D 形象。两条路都支持：自备 USDZ 手动导入，或和狗朋友一样走 Tripo 单图生成。
    var model3DLocalURL: URL?
    var model3DRemoteJobID: String?
    var model3DConvertJobID: String?
    var modelStatus: ModelBuildStatus = ModelBuildStatus.notStarted
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

    /// 生日到今天：满 N 岁 + 距上次生日过了多少天，用于首页"10岁 264天"展示。
    var ageText: String {
        guard let birthday else { return "" }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year], from: birthday, to: .now)
        let years = comps.year ?? 0
        let lastBirthday = cal.date(byAdding: .year, value: years, to: birthday) ?? birthday
        let days = cal.dateComponents([.day], from: lastBirthday, to: .now).day ?? 0
        return "\(years)岁 \(days)天"
    }
}

/// 和狗朋友共用 `ThreeDModelGenerator`：同一套超时、断点续传、不重复扣额度的逻辑，
/// 平平这边自动都有，不用另写一份。
extension DogProfile: Model3DHolder {}
