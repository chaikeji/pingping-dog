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

    /// 单条 route 触发。已经打过分且版本一致，直接跳过。
    /// fire-and-forget，不阻塞调用方。任何步骤失败静默 —— 大不了这次没贴纸。
    static func processIfNeeded(
        routeID: UUID,
        photos: [Data],
        scorerVersion: Int?,
        oldBestIndex: Int?,
        hasCutout: Bool,
        container: ModelContainer
    ) {
        guard needsWork(scorerVersion: scorerVersion, hasCutout: hasCutout), !photos.isEmpty else { return }
        Task.detached(priority: .utility) {
            await runOne(
                routeID: routeID,
                photos: photos,
                oldBestIndex: oldBestIndex,
                hasCutout: hasCutout,
                container: container
            )
        }
    }

    /// 批量补跑：串行处理，避免同时开一堆 Vision + 一堆 remove.bg 请求打爆内存 / 触发 rate limit。
    /// 上层筛好「还没打分 / 版本不对」的 route 传进来；此方法不再二次判断，谁进来谁跑。
    static func backfill(
        pendingRoutes: [PendingRoute],
        container: ModelContainer
    ) {
        guard !pendingRoutes.isEmpty else { return }
        Task.detached(priority: .utility) {
            for r in pendingRoutes {
                await runOne(
                    routeID: r.id,
                    photos: r.photos,
                    oldBestIndex: r.oldBestIndex,
                    hasCutout: r.hasCutout,
                    container: container
                )
            }
        }
    }

    /// 补跑候选。上层筛（`photoScorerVersion != current` 或没打过分）再传进来。
    struct PendingRoute: Sendable {
        let id: UUID
        let photos: [Data]
        let oldBestIndex: Int?
        let hasCutout: Bool
    }

    /// 版本已对齐且已经有 cutout（或本来就没值得抠的候选）→ 不用再跑。
    /// 拿来给上层筛出 pending 列表，也用于 processIfNeeded 二次兜底。
    static func needsWork(scorerVersion: Int?, hasCutout: Bool) -> Bool {
        scorerVersion != PhotoQualityScorer.currentVersion || !hasCutout
    }

    // MARK: - 内部实现

    private static func runOne(
        routeID: UUID,
        photos: [Data],
        oldBestIndex: Int?,
        hasCutout: Bool,
        container: ModelContainer
    ) async {
        let scores = PhotoQualityScorer.score(all: photos)

        // v3 起把 final gate 从 0.1 拉到 0.03 —— 跟 scorer 内部门槛一起放宽，
        // 之前有些猫狗照片打分 ~0.05 会被这行挡住不进抠图队列。
        var newBestIndex: Int? = nil
        if let bi = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[bi] > 0.03 {
            newBestIndex = bi
        }

        // 抠图触发条件：新挑出来的最佳照片跟老的不一样，或者老的还没抠成。
        // 一致 + 已有 cutout → 省一次 remove.bg 调用（省 $0.05）。
        let needsCutout = newBestIndex != nil
            && (newBestIndex != oldBestIndex || !hasCutout)

        var freshCutout: Data? = nil
        if needsCutout, let idx = newBestIndex {
            do {
                let raw = try await BackgroundRemovalService().removeBackground(imageData: photos[idx])
                freshCutout = CutoutCleaner.clean(pngData: raw)
            } catch {
                // key 没配 / 额度不够 / 网炸 —— 都不阻塞。photoScores 还是会存下来，
                // 下次不再重打分；但因为 cutoutData 是 nil、bestIndex 有值，
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
        fresh.photoScorerVersion = PhotoQualityScorer.currentVersion
        if let idx = newBestIndex {
            fresh.bestPhotoIndex = idx
            // 只在真的重新抠了的时候才覆盖 cutoutData；抠图失败但老 cutout 还在，就留着老的。
            if needsCutout, let freshCutout {
                fresh.cutoutData = freshCutout
            }
        } else {
            // 新版本判定这条 route 没值得抠的候选 —— 老 cutout 也清掉，视觉上不留错误贴纸。
            fresh.bestPhotoIndex = nil
            fresh.cutoutData = nil
        }
        try? bg.save()
    }
}
