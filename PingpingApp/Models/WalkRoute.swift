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
    /// 每张 photosData 对应的质量分（PhotoQualityScorer 算出来，越大越合适做贴纸）。
    /// JSON 编码的 [Double]，长度必须跟 photosData 对齐。**必须可选**：老库没这字段，
    /// 迁移填 nil；写非可选（哪怕默认 []）会跟 peeSpotsData 那次一样一读旧库就闪退。
    var photoScoresData: Data?
    /// 本次遛狗「最好一张」抠图 + 去狗绳后的 PNG（带 alpha）。nil 表示还没算 / 没值得抠的照片。
    /// 挑出来的是 photosData[bestPhotoIndex]。
    var cutoutData: Data?
    /// cutoutData 对应的原图在 photosData 里的下标。nil = 还没跑过挑选。
    var bestPhotoIndex: Int?
    /// 「次高分那张」的抠图 PNG。存在时进 [[MonthPhotoCalendarView]] 的借用池，给当月缺贴纸的日子借。
    /// nil = 只有一张照片 / 只有一张过打分门槛 / 抠图接口挂了。
    /// **必须可选**：老库没这字段（Batch: extra-cutout 才加），SwiftData 轻量迁移只给可选字段填 nil。
    var extraCutoutData: Data?
    /// extraCutoutData 对应的原图在 photosData 里的下标。Step 5 拿这个去重，
    /// 保证同一张原图整月不会既作次抠图贴纸又作方角原图出现。
    var extraCutoutPhotoIndex: Int?
    /// 打分时用的 [[PhotoQualityScorer]] 版本号。[[PhotoCutoutPipeline]] 比 currentVersion，
    /// 不一致就重打分（比如从 v1 只识狗升到 v2 识猫狗），必要时也会重跑抠图。
    /// nil = 老库还没打过 / 老版本打的但还没标版本号，走「重打」路径。
    var photoScorerVersion: Int?

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

    /// 跟 photosData 一一对应的质量分。长度不匹配就退化成空数组，读的时候自己兜底。
    @Transient
    var photoScores: [Double] {
        get {
            guard let data = photoScoresData,
                  let arr = try? JSONDecoder().decode([Double].self, from: data),
                  arr.count == photosData.count else { return [] }
            return arr
        }
        set { photoScoresData = try? JSONEncoder().encode(newValue) }
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
