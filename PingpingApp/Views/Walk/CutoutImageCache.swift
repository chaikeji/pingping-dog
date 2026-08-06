import UIKit
import ImageIO

/// [[MonthlyReviewGalleryView]] 月卡里贴纸 UIImage 的进程级缓存。
///
/// 为什么需要：`WalkRoute.cutoutData` 存的是 JPEG/PNG 压缩字节，`UIImage(data:)`
/// 每次都返回新实例，解码 bitmap 到 UIImageView 第一次绘制时才发生 —— 在主线程。
/// 画廊里 12 张月卡 × N 张贴纸首次绘制会把物理引擎的每帧挤到后面，看起来就是
/// "贴纸卡顿掉下来"。而且退出画廊 view 就销毁，下次进去又要重解一遍。
///
/// 修法：进程级 NSCache，key = "route.id-v版本-显示尺寸"（版本变了说明补跑重抠过，
/// key 就变，不用手动 invalidate）；后台按实际显示尺寸生成缩略图，避免把原始 PNG
/// 的完整像素位图带进月卡。NSCache 自己会在内存压力下驱逐。
final class CutoutImageCache {
    static let shared = CutoutImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let diagnosticLock = NSLock()
    private var activeDecodeKeys = Set<String>()

    private init() {
        // 24 张/月 × ~8 个月缓冲；再多也无所谓，NSCache 内存压力时自动淘汰。
        cache.countLimit = 200
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// 命中直接返回；未命中在后台线程按 maxPixelSize 降采样、解码一次再写回。
    /// data 是 Sendable，可以安全传进 detached task。
    func image(
        for key: String,
        data: Data,
        maxPixelSize: Int = 256,
        priority: TaskPriority = .userInitiated
    ) async -> UIImage? {
        let sizedKey = "\(key)-px\(maxPixelSize)"
        let nsKey = sizedKey as NSString
        if let cached = cache.object(forKey: nsKey) {
            SessionEventLog.log(
                "perf.image",
                context: "action=hit, priority=\(priority == .utility ? "utility" : "foreground"), key=\(sizedKey)"
            )
            return cached
        }
        diagnosticLock.lock()
        let duplicateDecode = activeDecodeKeys.contains(sizedKey)
        if !duplicateDecode { activeDecodeKeys.insert(sizedKey) }
        diagnosticLock.unlock()
        SessionEventLog.log(
            "perf.image",
            context: "action=\(duplicateDecode ? "duplicate-decode" : "miss"), priority=\(priority == .utility ? "utility" : "foreground"), key=\(sizedKey)"
        )
        let decodeStartedAt = ProcessInfo.processInfo.systemUptime
        let decoded = await Task.detached(priority: priority) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
        if let decoded {
            let pixelCost = Int(decoded.size.width * decoded.scale)
                * Int(decoded.size.height * decoded.scale) * 4
            cache.setObject(decoded, forKey: nsKey, cost: pixelCost)
        }
        if !duplicateDecode {
            diagnosticLock.lock()
            activeDecodeKeys.remove(sizedKey)
            diagnosticLock.unlock()
        }
        SessionEventLog.log(
            "perf.image",
            context: String(
                format: "action=decoded, elapsed=%.1fms, success=%@, duplicate=%@, key=%@",
                (ProcessInfo.processInfo.systemUptime - decodeStartedAt) * 1_000,
                decoded == nil ? "false" : "true",
                duplicateDecode ? "true" : "false",
                sizedKey
            )
        )
        return decoded
    }
}

/// 只把最近月份会用到的压缩图片提前解码进缓存；不创建视图、动画或物理引擎。
enum MileageImagePrewarmer {
    struct Request: Sendable {
        let key: String
        let data: Data
    }

    /// 遛狗页预热第一层月份卡：最近两个月的主贴纸。
    @MainActor
    static func galleryRequests(routes: [WalkRoute], monthLimit: Int = 2) -> [Request] {
        let recentMonths = recentMonthKeys(routes: routes, limit: monthLimit)
        return deduplicatedRequests(routes.compactMap { route in
            let monthKey = Calendar.current.component(.year, from: route.startDate) * 100
                + Calendar.current.component(.month, from: route.startDate)
            guard recentMonths.contains(monthKey), let data = route.cutoutData else { return nil }
            return Request(
                key: "\(route.id)-v\(route.photoScorerVersion ?? 0)",
                data: data
            )
        })
    }

    /// 第一层月份列表预热第二层月历：最近两个月的主贴纸、额外贴纸和每天一张备用原图。
    @MainActor
    static func calendarRequests(routes: [WalkRoute], monthLimit: Int = 2) -> [Request] {
        let recentMonths = recentMonthKeys(routes: routes, limit: monthLimit)
        let recentRoutes = routes.filter { route in
            let components = Calendar.current.dateComponents([.year, .month], from: route.startDate)
            return recentMonths.contains((components.year ?? 0) * 100 + (components.month ?? 0))
        }
        var requests: [Request] = []
        for route in recentRoutes {
            let version = route.photoScorerVersion ?? 0
            if let data = route.cutoutData {
                requests.append(Request(key: "\(route.id)-v\(version)", data: data))
            }
            if let data = route.extraCutoutData {
                requests.append(Request(key: "\(route.id)-extra-v\(version)", data: data))
            }
        }

        let routesByDay = Dictionary(grouping: recentRoutes) { route in
            let c = Calendar.current.dateComponents([.year, .month, .day], from: route.startDate)
            return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        }
        for dayRoutes in routesByDay.values {
            guard let fallback = dayRoutes.max(by: { $0.photosData.count < $1.photosData.count }),
                  let data = fallback.photosData.first else { continue }
            requests.append(Request(key: "\(fallback.id)-fallback-0", data: data))
        }
        return deduplicatedRequests(requests)
    }

    /// 小批量、低优先级预热；父级 SwiftUI task 取消后会在批次边界立即停止。
    static func prewarm(_ requests: [Request], batchSize: Int, source: String) async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        SessionEventLog.log(
            "perf.prewarm.start",
            context: "source=\(source), requests=\(requests.count), batchSize=\(batchSize)"
        )
        for start in stride(from: 0, to: requests.count, by: batchSize) {
            guard !Task.isCancelled else {
                SessionEventLog.log(
                    "perf.prewarm.cancel",
                    context: "source=\(source), completedBeforeIndex=\(start), total=\(requests.count)"
                )
                return
            }
            let batch = requests[start..<min(start + batchSize, requests.count)]
            await withTaskGroup(of: Void.self) { group in
                for request in batch {
                    group.addTask {
                        guard !Task.isCancelled else { return }
                        _ = await CutoutImageCache.shared.image(
                            for: request.key,
                            data: request.data,
                            maxPixelSize: 256,
                            priority: .utility
                        )
                    }
                }
            }
        }
        SessionEventLog.log(
            "perf.prewarm.end",
            context: String(
                format: "source=%@, requests=%d, elapsed=%.1fms",
                source,
                requests.count,
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
        )
    }

    @MainActor
    private static func recentMonthKeys(routes: [WalkRoute], limit: Int) -> Set<Int> {
        let keys = Set(routes.map { route in
            let c = Calendar.current.dateComponents([.year, .month], from: route.startDate)
            return (c.year ?? 0) * 100 + (c.month ?? 0)
        })
        return Set(keys.sorted(by: >).prefix(limit))
    }

    private static func deduplicatedRequests(_ requests: [Request]) -> [Request] {
        var seen = Set<String>()
        return requests.filter { seen.insert($0.key).inserted }
    }
}
