import UIKit
import QuickLookThumbnailing

/// 狗朋友列表里显示的 3D 缩略图。
///
/// 列表里不能每行塞一个 RealityView：单个模型 50 MB 以上，几只狗就能把内存吃干、滚动也会卡。
/// 这里用 QuickLook 把模型渲染成一张静态图，存盘 + 内存各缓存一份，之后当普通图片显示。
enum ModelThumbnail {
    private static let cache = NSCache<NSString, UIImage>()

    /// 取缩略图：内存 → 磁盘 → 现渲染。渲染不出来返回 nil，调用方回落到照片。
    static func image(ownerID: UUID, modelURL: URL, size: CGSize, scale: CGFloat) async -> UIImage? {
        let key = ownerID.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let file = try? ModelStorage.thumbnailURL(ownerID: ownerID) else { return nil }
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            cache.setObject(image, forKey: key)
            return image
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: modelURL,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request) else { return nil }

        let image = representation.uiImage
        if let data = image.jpegData(compressionQuality: 0.9) { try? data.write(to: file) }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 模型换了就得把旧缩略图清掉，否则列表上会一直是上一个模型的样子。
    static func invalidate(ownerID: UUID) {
        cache.removeObject(forKey: ownerID.uuidString as NSString)
        if let file = try? ModelStorage.thumbnailURL(ownerID: ownerID) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
