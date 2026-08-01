import UIKit

/// [[MonthlyReviewGalleryView]] 月卡里贴纸 UIImage 的进程级缓存。
///
/// 为什么需要：`WalkRoute.cutoutData` 存的是 JPEG/PNG 压缩字节，`UIImage(data:)`
/// 每次都返回新实例，解码 bitmap 到 UIImageView 第一次绘制时才发生 —— 在主线程。
/// 画廊里 12 张月卡 × N 张贴纸首次绘制会把物理引擎的每帧挤到后面，看起来就是
/// "贴纸卡顿掉下来"。而且退出画廊 view 就销毁，下次进去又要重解一遍。
///
/// 修法：进程级 NSCache，key = "route.id-v版本"（版本变了说明补跑重抠过，key 就变，
/// 不用手动 invalidate）；缓存的是**已经 preparingForDisplay 解好位图的 UIImage**，
/// `UIImageView(image:)` 之后不再有隐性主线程解码。NSCache 自己会在内存压力下驱逐。
final class CutoutImageCache {
    static let shared = CutoutImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // 24 张/月 × ~8 个月缓冲；再多也无所谓，NSCache 内存压力时自动淘汰。
        cache.countLimit = 200
    }

    /// 命中直接返回；未命中在后台线程 `preparingForDisplay` 解一次再写回。
    /// data 是 Sendable，可以安全传进 detached task。
    func image(for key: String, data: Data) async -> UIImage? {
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let raw = UIImage(data: data) else { return nil }
            // preparingForDisplay 是同步阻塞版本；异步版是 prepareForDisplay(completionHandler:)。
            // 我们已经在 detached 后台里了，同步版即可。返回 nil 就退回原图（比如 symbol image）。
            return raw.preparingForDisplay() ?? raw
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: nsKey)
        }
        return decoded
    }
}
