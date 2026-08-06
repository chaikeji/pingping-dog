import Foundation
import UIKit

/// 路线小图缓存：完整 GPS 点只在后台处理一次，之后页面直接显示一张很小的 PNG。
/// 同时落到 Application Support，App 重启后也不用再遍历整条路线。
final class RouteThumbnailCache {
    static let shared = RouteThumbnailCache()

    private let memory = NSCache<NSString, UIImage>()

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 16 * 1024 * 1024
    }

    func image(routeID: UUID, points: [RoutePoint], pixelSize: Int = 240) async -> UIImage? {
        let key = "\(routeID)-n\(points.count)-px\(pixelSize)"
        if let cached = memory.object(forKey: key as NSString) { return cached }

        let fileURL = Self.fileURL(for: key)
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            if let data = try? Data(contentsOf: fileURL), let cached = UIImage(data: data) {
                return cached.preparingForDisplay() ?? cached
            }
            guard let rendered = Self.render(points: points, pixelSize: pixelSize) else { return nil }
            if let data = rendered.pngData() { try? data.write(to: fileURL, options: .atomic) }
            return rendered
        }.value

        if let image {
            memory.setObject(image, forKey: key as NSString, cost: pixelSize * pixelSize * 4)
        }
        return image
    }

    private static func fileURL(for key: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent("route_thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(key).appendingPathExtension("png")
    }

    private static func render(points: [RoutePoint], pixelSize: Int) -> UIImage? {
        guard points.count >= 2, pixelSize > 0 else { return nil }

        // 小图不需要数千个 GPS 点。均匀保留最多 180 点，起终点一定保留。
        let step = max(1, Int(ceil(Double(points.count) / 180.0)))
        var sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last,
           sampled.last?.latitude != last.latitude || sampled.last?.longitude != last.longitude {
            sampled.append(last)
        }

        let lats = sampled.map(\.latitude)
        let lons = sampled.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let width = pixelSize
        let height = pixelSize
        let bytesPerRow = width * 4
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let latSpan = max(maxLat - minLat, 0.00001)
        let lonSpan = max(maxLon - minLon, 0.00001)
        let usable = CGFloat(pixelSize) * 0.84
        let scale = min(usable / CGFloat(lonSpan), usable / CGFloat(latSpan))
        let drawnW = CGFloat(lonSpan) * scale
        let drawnH = CGFloat(latSpan) * scale
        let xOffset = (CGFloat(pixelSize) - drawnW) / 2
        let yOffset = (CGFloat(pixelSize) - drawnH) / 2

        context.setStrokeColor(red: 63.0 / 255, green: 157.0 / 255, blue: 84.0 / 255, alpha: 1)
        context.setLineWidth(5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for (index, point) in sampled.enumerated() {
            let x = xOffset + CGFloat(point.longitude - minLon) * scale
            // Core Graphics 原点在左下；纬度越高就应该画得越靠上。
            let y = yOffset + CGFloat(point.latitude - minLat) * scale
            if index == 0 { context.move(to: CGPoint(x: x, y: y)) }
            else { context.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.strokePath()

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
