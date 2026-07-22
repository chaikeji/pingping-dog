import Foundation
import SwiftData

/// 一次遛狗记录（PRD §4.3 v1.5）。除轨迹外，记录本次的尿尿 / 拉屎计数、遇到的狗朋友、
/// 拍的照片，以及当天累计是否达标（≥15min，用于联动「完美的一天」的遛狗习惯）。
@Model
final class WalkRoute {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var durationSeconds: Int          // 实际计时时长（扣掉暂停）
    var pointsData: Data
    var distanceMeters: Double
    var isKnownRoute: Bool
    var matchedKnownRouteID: UUID?
    var peeCount: Int                 // 尿尿次数
    var poopCount: Int                // 拉屎次数（+1 联动「便便观察」打卡）
    /// 尿尿 / 拉屎图钉的落点（JSON 编码的 [RoutePoint]）。
    /// **必须是可选**：老库里没有这两个字段，SwiftData 轻量迁移只能给可选字段填 nil；
    /// 写成非可选（哪怕带默认值）会跟 DogProfile.modelStatus 那次一样，一读旧记录就闪退。
    /// 见 PRD §4.1 内的坑记录。
    var peeSpotsData: Data?
    var poopSpotsData: Data?
    var metDogFriendIDs: [UUID]       // 本次遇到的狗朋友（各 +1 亲密度）
    var photosData: [Data]            // 本次拍的照片（JPEG）
    var meetsDailyGoal: Bool          // 当天累计 ≥15min 达标
    var ownerID: String?

    @Transient
    var points: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: pointsData)) ?? [] }
        set { pointsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    @Transient
    var peeSpots: [RoutePoint] {
        get { peeSpotsData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? [] }
        set { peeSpotsData = try? JSONEncoder().encode(newValue) }
    }

    @Transient
    var poopSpots: [RoutePoint] {
        get { poopSpotsData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? [] }
        set { poopSpotsData = try? JSONEncoder().encode(newValue) }
    }

    init(
        startDate: Date = .now,
        points: [RoutePoint] = [],
        distanceMeters: Double = 0,
        durationSeconds: Int = 0,
        peeCount: Int = 0,
        poopCount: Int = 0,
        peeSpots: [RoutePoint] = [],
        poopSpots: [RoutePoint] = [],
        metDogFriendIDs: [UUID] = [],
        photosData: [Data] = [],
        meetsDailyGoal: Bool = false,
        ownerID: String? = nil
    ) {
        self.id = UUID()
        self.startDate = startDate
        self.durationSeconds = durationSeconds
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.distanceMeters = distanceMeters
        self.isKnownRoute = false
        self.peeCount = peeCount
        self.poopCount = poopCount
        self.peeSpotsData = peeSpots.isEmpty ? nil : (try? JSONEncoder().encode(peeSpots))
        self.poopSpotsData = poopSpots.isEmpty ? nil : (try? JSONEncoder().encode(poopSpots))
        self.metDogFriendIDs = metDogFriendIDs
        self.photosData = photosData
        self.meetsDailyGoal = meetsDailyGoal
        self.ownerID = ownerID
    }
}
