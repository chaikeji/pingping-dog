import Foundation
import SwiftData

enum ModelBuildStatus: String, Codable {
    case notStarted, queued, processing, ready, failed
}

/// 3D 建模的公共字段，`DogProfile`（平平自己）和 `DogFriend`（狗朋友）都实现这个协议，
/// 这样 `ThreeDModelGenerator` 可以复用同一套生成逻辑，不用为两个 model 各写一份。
protocol Model3DHolder: AnyObject {
    var id: UUID { get }
    var model3DLocalURL: URL? { get set }
    var model3DRemoteJobID: String? { get set }
    /// 转 USDZ 那步的任务 id。单独存是为了断点续传：
    /// 生成和转换都在服务端跑完、只是下载断了的话，重试直接拿这个任务的结果，不用重新花额度。
    var model3DConvertJobID: String? { get set }
    var modelStatus: ModelBuildStatus { get set }
    var modelErrorMessage: String? { get set }
}

/// 狗朋友（PRD §4.2 v1.5）：名字必填，另记性别 / 手填年龄 / 认识日期 / 亲密度。
/// 不再有品种、主人。亲密度随遛狗遇见 +1；认识日期供以后「认识纪念」。走单图 Tripo 建模。
@Model
final class DogFriend {
    var id: UUID
    var name: String
    var gender: String        // "公" / "母" / ""（未填）
    var ageText: String       // 手填年龄，多数狗不知生日故不记生日
    var metDate: Date         // 认识日期
    var intimacy: Int         // 亲密度，默认 0，遛狗遇见 +1
    var avatarData: Data?     // 头像 / 生成 3D 的原图
    var model3DLocalURL: URL?
    var model3DRemoteJobID: String?
    var model3DConvertJobID: String?
    var modelStatus: ModelBuildStatus
    var modelErrorMessage: String?
    var createdAt: Date
    var ownerID: String?

    init(
        name: String,
        gender: String = "",
        ageText: String = "",
        metDate: Date = .now,
        avatarData: Data? = nil,
        ownerID: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.gender = gender
        self.ageText = ageText
        self.metDate = metDate
        self.intimacy = 0
        self.avatarData = avatarData
        self.modelStatus = .notStarted
        self.createdAt = .now
        self.ownerID = ownerID
    }
}

extension DogFriend: Model3DHolder {}
