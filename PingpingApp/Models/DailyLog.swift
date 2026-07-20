import Foundation
import SwiftData

/// 完美的一天的档位小太阳。日期条与挑战弹窗共用。
enum SunTier: String, Codable {
    case gold    // 金 80–100%
    case silver  // 银 60–80%
    case bronze  // 铜 40–60%
    case gray    // 灰 <40%（0 = 当天什么都没做）

    /// 按完美值 % 归档。
    static func from(score: Int) -> SunTier {
        switch score {
        case 80...: return .gold
        case 60..<80: return .silver
        case 40..<60: return .bronze
        default: return .gray
        }
    }
}

/// 完美的一天：每天一条记录。日期条历史、以后的通知引擎都取这张表。
@Model
final class DailyLog {
    var id: UUID
    /// 归一化到当天**午夜**（见 `PetDay.start`）。
    /// 早期版本存的是 04:00，`PerfectDayView.normalizeLegacyLogDates()` 会就地迁移。
    var date: Date
    var completedHabitIDs: [UUID]
    var healthOK: Bool
    var cleanOK: Bool
    /// 封顶后的完美值 %（0–100），与日期条徽章一致。
    var perfectScore: Int
    var sunTier: SunTier
    var ownerID: String?

    init(date: Date, completedHabitIDs: [UUID] = [], healthOK: Bool = true, cleanOK: Bool = true, perfectScore: Int = 0, sunTier: SunTier = .gray, ownerID: String? = nil) {
        self.id = UUID()
        self.date = date
        self.completedHabitIDs = completedHabitIDs
        self.healthOK = healthOK
        self.cleanOK = cleanOK
        self.perfectScore = perfectScore
        self.sunTier = sunTier
        self.ownerID = ownerID
    }
}
