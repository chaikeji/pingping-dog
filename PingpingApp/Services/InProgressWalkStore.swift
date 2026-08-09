import Foundation

/// 遛狗中的会话快照：App 被 kill / 手机关机时保底能捞回来的最小状态。
/// 只带回轨迹和计次（peeCount / poopCount / metFriendIDs），照片和图钉丢掉 ——
/// 用户明确要求 §6 交互，别为了保 5MB 照片让 Documents 越写越大。
struct InProgressWalkSnapshot: Codable {
    var startDate: Date              // 会话开始时间，也是 UI 上「XX 分钟前开始」的锚
    var savedAt: Date                // 最近一次刷盘时间，也是判断这份会话是否仍新鲜的依据
    var points: [RoutePoint]         // 轨迹全量
    var distanceMeters: Double       // 快照时刻的累计距离，供续遛提示显示「已走 X.XX 公里」
    var elapsedSeconds: Int
    var peeCount: Int
    var poopCount: Int
    var metFriendIDs: [UUID]
    var isPaused: Bool
}

/// 断点续遛的持久化层：Application Support 里放一个 JSON 文件。
///
/// 为什么不用 UserDefaults：轨迹可能有几百个点，UserDefaults 存大 blob 会拖慢启动。
/// 为什么不用 SwiftData：SwiftData 迁移一挂全库崩，而这份快照本就是「丢了就丢了」的兜底数据，
/// 用最朴素的 JSON 文件不牵连主库。
enum InProgressWalkStore {
    /// 最后一次成功保存后超过 2h 才视为废弃；不能按开始时间算，否则长时间遛狗会被误删。
    static let expirationInterval: TimeInterval = 2 * 3600

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("walk_in_progress.json")
    }

    static func save(_ snapshot: InProgressWalkSnapshot) {
        var s = snapshot
        s.savedAt = .now
        do {
            let data = try JSONEncoder().encode(s)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            SessionEventLog.log("snapshot.save.failed", context: "error=\(error.localizedDescription), points=\(s.points.count)")
        }
    }

    /// 读取当前快照；已过期就顺手清掉、返回 nil。
    static func loadValid() -> InProgressWalkSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else {
            SessionEventLog.log("snapshot.load.failed", context: "reason=read")
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(InProgressWalkSnapshot.self, from: data) else {
            SessionEventLog.log("snapshot.load.failed", context: "reason=decode, bytes=\(data.count)")
            return nil
        }
        let idleSeconds = Date.now.timeIntervalSince(snapshot.savedAt)
        if idleSeconds > expirationInterval {
            SessionEventLog.log("snapshot.expired", context: "idle=\(Int(idleSeconds))s, age=\(Int(Date.now.timeIntervalSince(snapshot.startDate)))s, points=\(snapshot.points.count)")
            clear()
            return nil
        }
        return snapshot
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
