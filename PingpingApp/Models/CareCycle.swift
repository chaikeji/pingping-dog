import Foundation
import SwiftData

/// 周期护理项的大类：清洁类逾期 → cleanOK=false；健康类逾期 → healthOK=false。
enum CareCategory: String, Codable {
    case clean   // 清洁
    case health  // 健康
}

/// 六个周期护理项，各自知道自己属于哪一类、默认周期几天。
enum CareCycleType: String, Codable, CaseIterable {
    case nailTrim        // 剪指甲
    case earClean        // 清耳朵
    case toothBrush      // 刷牙
    case externalDeworm  // 体外驱虫
    case internalDeworm  // 体内驱虫
    case checkup         // 定期体检

    var category: CareCategory {
        switch self {
        case .nailTrim, .earClean, .toothBrush: return .clean
        case .externalDeworm, .internalDeworm, .checkup: return .health
        }
    }

    /// 默认周期（天）。以后可在设置里改，改后写入 CareCycle.cycleDays。
    var defaultCycleDays: Int {
        switch self {
        case .toothBrush: return 3
        case .earClean: return 10
        case .nailTrim: return 21
        case .externalDeworm: return 30
        case .internalDeworm: return 90
        case .checkup: return 365
        }
    }

    var displayName: String {
        switch self {
        case .nailTrim: return "剪指甲"
        case .earClean: return "清耳朵"
        case .toothBrush: return "刷牙"
        case .externalDeworm: return "体外驱虫"
        case .internalDeworm: return "体内驱虫"
        case .checkup: return "定期体检"
        }
    }
}

/// 一个周期护理项的当前状态。逾期判断供首页通知池、完美的一天封顶、状态可视化共用。
@Model
final class CareCycle {
    var id: UUID
    var type: CareCycleType
    var cycleDays: Int
    var lastDoneDate: Date?
    var ownerID: String?

    init(type: CareCycleType, cycleDays: Int? = nil, lastDoneDate: Date? = nil, ownerID: String? = nil) {
        self.id = UUID()
        self.type = type
        self.cycleDays = cycleDays ?? type.defaultCycleDays
        self.lastDoneDate = lastDoneDate
        self.ownerID = ownerID
    }

    /// 从未记录过「上次完成日」也视为逾期（提醒用户先去登记）。
    var isOverdue: Bool {
        guard let lastDoneDate else { return true }
        let due = Calendar.current.date(byAdding: .day, value: cycleDays, to: lastDoneDate) ?? lastDoneDate
        return Date.now > due
    }

    /// 首次启动时写入的六项（lastDoneDate 留空，等用户去设置里登记）。
    static func defaults() -> [CareCycle] {
        CareCycleType.allCases.map { CareCycle(type: $0) }
    }
}
