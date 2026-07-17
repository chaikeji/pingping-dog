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
    var metDogFriendIDs: [UUID]       // 本次遇到的狗朋友（各 +1 亲密度）
    var photosData: [Data]            // 本次拍的照片（JPEG）
    var meetsDailyGoal: Bool          // 当天累计 ≥15min 达标
    var ownerID: String?

    @Transient
    var points: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: pointsData)) ?? [] }
        set { pointsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        startDate: Date = .now,
        points: [RoutePoint] = [],
        distanceMeters: Double = 0,
        durationSeconds: Int = 0,
        peeCount: Int = 0,
        poopCount: Int = 0,
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
        self.metDogFriendIDs = metDogFriendIDs
        self.photosData = photosData
        self.meetsDailyGoal = meetsDailyGoal
        self.ownerID = ownerID
    }
}
