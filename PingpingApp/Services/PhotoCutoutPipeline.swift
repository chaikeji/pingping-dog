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
        oldExtraIndex: Int?,
        hasCutout: Bool,
        hasExtraCutout: Bool,
        container: ModelContainer
    ) {
        guard needsWork(scorerVersion: scorerVersion, hasCutout: hasCutout), !photos.isEmpty else { return }
        Task.detached(priority: .utility) {
            await runOne(
                routeID: routeID,
                photos: photos,
                oldBestIndex: oldBestIndex,
                oldExtraIndex: oldExtraIndex,
                hasCutout: hasCutout,
                hasExtraCutout: hasExtraCutout,
                container: container
            )
        }
    }

    /// 批量补跑：串行处理，避免同时开一堆 Vision + 一堆 remove.bg 请求打爆内存 / 触发 rate limit。
    /// 上层筛好「还没打分 / 版本不对」的 route 传进来；此方法不再二次判断，谁进来谁跑。
    /// 每条 route 之间 sleep 500ms —— Vision 走 Neural Engine + remove.bg 网络回来后写 SwiftData
    /// 连着跑手机会烫；给硬件一段喘息，用户等的时间没差多少（本来就是背景补跑）。
    static func backfill(
        pendingRoutes: [PendingRoute],
        container: ModelContainer
    ) {
        guard !pendingRoutes.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (i, r) in pendingRoutes.enumerated() {
                await runOne(
                    routeID: r.id,
                    photos: r.photos,
                    oldBestIndex: r.oldBestIndex,
                    oldExtraIndex: r.oldExtraIndex,
                    hasCutout: r.hasCutout,
                    hasExtraCutout: r.hasExtraCutout,
                    container: container
                )
                if i < pendingRoutes.count - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    /// 补跑候选。上层筛（`photoScorerVersion != current` 或没打过分）再传进来。
    struct PendingRoute: Sendable {
        let id: UUID
        let photos: [Data]
        let oldBestIndex: Int?
        let oldExtraIndex: Int?
        let hasCutout: Bool
        let hasExtraCutout: Bool
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
        oldExtraIndex: Int?,
        hasCutout: Bool,
        hasExtraCutout: Bool,
        container: ModelContainer
    ) async {
        let scores = PhotoQualityScorer.score(all: photos)

        // v3 起把 final gate 从 0.1 拉到 0.03 —— 跟 scorer 内部门槛一起放宽，
        // 之前有些猫狗照片打分 ~0.05 会被这行挡住不进抠图队列。
        let sortedIdx = scores.indices.sorted { scores[$0] > scores[$1] }
        let qualifiers = sortedIdx.filter { scores[$0] > 0.03 }
        let newBestIndex: Int? = qualifiers.first
        // v4 起挑次高分作为"额外贴纸"，进日历借用池给空日兜底；只有一张过门槛就没有 extra。
        let newExtraIndex: Int? = qualifiers.count >= 2 ? qualifiers[1] : nil

        // 主抠图触发条件：新最佳跟老的不一样，或者老的还没抠成。
        // 一致 + 已有 cutout → 省一次 remove.bg 调用（省 0.25 credit）。
        let needsCutout = newBestIndex != nil
            && (newBestIndex != oldBestIndex || !hasCutout)
        // 次抠图触发条件同理，独立判断。
        let needsExtraCutout = newExtraIndex != nil
            && (newExtraIndex != oldExtraIndex || !hasExtraCutout)

        // 主 + 次两次抠图各自独立跑，一方挂了不影响另一方。
        var freshCutout: Data? = nil
        if needsCutout, let idx = newBestIndex {
            do {
                let raw = try await BackgroundRemovalService().removeBackground(imageData: photos[idx])
                freshCutout = CutoutCleaner.clean(pngData: raw)
            } catch {
                // key 没配 / 额度不够 / 网炸 —— 都不阻塞。photoScores 还是会存下来，
                // 下次不再重打分；但因为 cutoutData 是 nil、bestIndex 有值，
                // 上层可以判断「打了分但抠图失败」和「压根没打分」的区别。
                print("[BackgroundRemoval] route \(routeID.uuidString.prefix(6)) best failed: \(error.localizedDescription)")
            }
        }
        var freshExtraCutout: Data? = nil
        if needsExtraCutout, let idx = newExtraIndex {
            do {
                let raw = try await BackgroundRemovalService().removeBackground(imageData: photos[idx])
                freshExtraCutout = CutoutCleaner.clean(pngData: raw)
            } catch {
                print("[BackgroundRemoval] route \(routeID.uuidString.prefix(6)) extra failed: \(error.localizedDescription)")
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
        // 次抠图同套逻辑，独立于主：新选出来了就更新 index；实抠成功了才覆盖 data。
        if let idx = newExtraIndex {
            fresh.extraCutoutPhotoIndex = idx
            if needsExtraCutout, let freshExtraCutout {
                fresh.extraCutoutData = freshExtraCutout
            }
        } else {
            fresh.extraCutoutPhotoIndex = nil
            fresh.extraCutoutData = nil
        }
        try? bg.save()
    }
}
