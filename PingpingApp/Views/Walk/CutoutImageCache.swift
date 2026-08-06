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

    private init() {
        // 24 张/月 × ~8 个月缓冲；再多也无所谓，NSCache 内存压力时自动淘汰。
        cache.countLimit = 200
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// 命中直接返回；未命中在后台线程按 maxPixelSize 降采样、解码一次再写回。
    /// data 是 Sendable，可以安全传进 detached task。
    func image(for key: String, data: Data, maxPixelSize: Int = 256) async -> UIImage? {
        let sizedKey = "\(key)-px\(maxPixelSize)"
        let nsKey = sizedKey as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
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
        return decoded
    }
}
