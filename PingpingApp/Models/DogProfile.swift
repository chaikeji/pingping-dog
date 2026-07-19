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
    var modelErrorMessage: String?

    /// 存成可选的原始字符串，而不是直接存 `ModelBuildStatus`。
    ///
    /// 这个字段是后加到 DogProfile 上的，而库里已经有一条按旧结构存的平平记录。
    /// SwiftData 的轻量迁移能给可选字段填 nil，但给非可选枚举填不出默认值 ——
    /// 之前写成 `var modelStatus: ModelBuildStatus` 的结果就是一读旧记录就闪退，
    /// 而全 App 只有设置页读它，所以表现为「点设置崩、首页正常」。
    /// DogFriend 那边能直接存枚举，是因为它从建表起就有这个字段，不涉及迁移。
    var modelStatusRaw: String?

    init(name: String = "平平", breed: String = "", birthday: Date? = nil, avatarData: Data? = nil, ownerID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.breed = breed
        self.birthday = birthday
        self.avatarData = avatarData
        self.ownerID = ownerID
        self.createdAt = .now
    }

    /// 协议要的非可选枚举，由上面那个可选原始值转换而来；旧记录没值就当「未开始」。
    var modelStatus: ModelBuildStatus {
        get { modelStatusRaw.flatMap(ModelBuildStatus.init(rawValue:)) ?? .notStarted }
        set { modelStatusRaw = newValue.rawValue }
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
