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

    /// 平平首页的 3D 形象：自备 USDZ 文件导入后缓存在本地，不走 Tripo 生成链路。
    var model3DLocalURL: URL?

    init(name: String = "平平", breed: String = "", birthday: Date? = nil, avatarData: Data? = nil, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.breed = breed
        self.birthday = birthday
        self.avatarData = avatarData
        self.ownerID = ownerID
        self.createdAt = .now
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
