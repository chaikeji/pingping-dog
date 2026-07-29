import Foundation
import SwiftData

/// 遛狗照片 → 贴纸的完整链路：Vision 打分 → 挑最好一张 → [[BackgroundRemovalService]] 抠图
/// → [[CutoutCleaner]] 去狗绳 + 描边 → 写回 [[WalkRoute]] 的 `cutoutData`。
///
/// 两个入口：
/// - `processIfNeeded`：单条 route，[[WalkSessionViewModel]] finish() 用。
/// - `backfill`：一批 route 串行跑，[[MonthPhotoCalendarView]] onAppear 用来补跑老 route。
///
/// 老 route 补跑很重要：抠图 pipeline 是 `647834e` commit 才上，之前的 route 从没进过。
/// 用户第一次打开月度日历时把本月的老照片补一遍，之后就跟新 route 一视同仁。
enum PhotoCutoutPipeline {

    /// 单条 route 触发。已经打过分（`alreadyScored == true`）或没照片，直接跳过。
    /// fire-and-forget，不阻塞调用方。任何步骤失败静默 —— 大不了这次没贴纸。
    static func processIfNeeded(
        routeID: UUID,
        photos: [Data],
        alreadyScored: Bool,
        container: ModelContainer
    ) {
        guard !alreadyScored, !photos.isEmpty else { return }
        Task.detached(priority: .utility) {
            await runOne(routeID: routeID, photos: photos, container: container)
        }
    }

    /// 批量补跑：串行处理，避免同时开一堆 Vision + 一堆 remove.bg 请求打爆内存 / 触发 rate limit。
    /// 上层筛好「还没打分」的 route 传进来；此方法不再二次判断，谁进来谁跑。
    static func backfill(
        pendingRoutes: [(id: UUID, photos: [Data])],
        container: ModelContainer
    ) {
        guard !pendingRoutes.isEmpty else { return }
        Task.detached(priority: .utility) {
            for r in pendingRoutes {
                await runOne(routeID: r.id, photos: r.photos, container: container)
            }
        }
    }

    // MARK: - 内部实现

    private static func runOne(
        routeID: UUID,
        photos: [Data],
        container: ModelContainer
    ) async {
        let scores = PhotoQualityScorer.score(all: photos)

        var bestIndex: Int? = nil
        if let bi = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[bi] > 0.1 {
            bestIndex = bi
        }

        var cutout: Data? = nil
        if let idx = bestIndex {
            do {
                let raw = try await BackgroundRemovalService().removeBackground(imageData: photos[idx])
                cutout = CutoutCleaner.clean(pngData: raw)
            } catch {
                // key 没配 / 额度不够 / 网炸 —— 都不阻塞。photoScores 还是会存下来，
                // 下次不再打分；但因为 cutoutData 是 nil、bestIndex 有值，
                // 上层可以判断「打了分但抠图失败」和「压根没打分」的区别。
                print("[BackgroundRemoval] route \(routeID.uuidString.prefix(6)) failed: \(error.localizedDescription)")
            }
        }

        // 新 ModelContext：ModelContainer 是 Sendable，主库那个 @MainActor context 不能跨线程。
        // 存完 SwiftData 会自动通知其它 context 刷新，@Query 就能看见新数据。
        let bg = ModelContext(container)
        let descriptor = FetchDescriptor<WalkRoute>(predicate: #Predicate { $0.id == routeID })
        guard let fresh = try? bg.fetch(descriptor).first else { return }
        fresh.photoScores = scores
        if let idx = bestIndex {
            fresh.bestPhotoIndex = idx
            fresh.cutoutData = cutout
        }
        try? bg.save()
    }
}
