import UIKit
import CoreImage

/// 抠图后清洗：干掉狗绳 + 悬空的片段（比如牵狗绳那只手）。
/// remove.bg 会把狗绳当主体一起抠出来，人手也可能残留一小块。
/// 两步清洗都是本地跑的，跟 [[BackgroundRemovalService]] 抠完立刻串起来。
///
/// 1. 形态学开运算（Core Image `CIMorphologyMinimum` → `CIMorphologyMaximum`）：
///    先侵蚀再膨胀，比 radius 细的结构直接消失，狗身粗结构被啃薄一层后又长回来。
/// 2. 只保留 alpha channel 里最大的连通块：狗绳被步骤 1 切断后，牵狗绳那只手会
///    变成漂浮的小岛，用 BFS 把它抹掉。
enum CutoutCleaner {

    /// 输入 remove.bg 返回的 PNG（带 alpha），输出清洗 + 白描边后的 PNG。任何一步失败退回原图。
    /// openingRadius 是狗绳粗细的经验值：iPhone 拍中距离的狗，绳径大约 2-4px；给 3 兜住多数情况。
    /// strokeRadius 是烘进图里的描边像素半径：preview 尺寸是 612×408，我们日历格 3x 渲染 ~150px，
    /// 4× 缩放看，10 像素描边到格子里正好是 2-3pt，肉眼刚看得出「贴纸感」。
    static func clean(
        pngData: Data,
        openingRadius: Double = 3.0,
        strokeRadius: Double = 10.0
    ) -> Data {
        guard let uiImage = UIImage(data: pngData),
              let cgImage = uiImage.cgImage else { return pngData }

        let opened = morphologicalOpen(cgImage, radius: openingRadius) ?? cgImage
        let largestBlob = keepLargestBlob(opened) ?? opened
        let stroked = addWhiteStroke(largestBlob, radius: strokeRadius) ?? largestBlob
        return UIImage(cgImage: stroked).pngData() ?? pngData
    }

    /// 交给 3D 建模的版本：去细绳、去悬空碎片，但不添加贴纸用的白描边。
    /// auto 输出通常明显大于 preview，因此按图片短边自适应开运算半径。
    static func cleanForModel(pngData: Data) -> Data {
        guard let uiImage = UIImage(data: pngData),
              let cgImage = uiImage.cgImage else { return pngData }

        let shortSide = Double(min(cgImage.width, cgImage.height))
        let openingRadius = min(8.0, max(3.0, shortSide / 200.0))
        let opened = morphologicalOpen(cgImage, radius: openingRadius) ?? cgImage
        let largestBlob = keepLargestBlob(opened) ?? opened
        return UIImage(cgImage: largestBlob).pngData() ?? pngData
    }

    // MARK: - 形态学开运算（GPU，靠 Core Image）

    /// 直接对 RGBA 一起做 open。RGB 边缘可能被啃几像素、颜色略脏，
    /// 但我们外面还要围一圈白描边，那点脏刚好被盖掉，不用为它额外做通道分离。
    private static func morphologicalOpen(_ image: CGImage, radius: Double) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let eroded = ci.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])
        let opened = eroded.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
        // extent 用原图的：CIMorphologyMaximum 会把 extent 撑得比原图大一圈。
        return sharedContext.createCGImage(opened, from: ci.extent)
    }

    private static let sharedContext: CIContext = {
        // workingColorSpace = nil 避免自动色彩转换，形态学是像素级操作，不需要色彩管理。
        CIContext(options: [.workingColorSpace: NSNull()])
    }()

    // MARK: - 最大连通块

    /// 把 alpha 二值化后 BFS 找最大连通块，其它像素 alpha + RGB 一起归零。
    /// 阈值 32：alpha < 32 认作透明，避免半透明羽化边被当成小碎块。
    private static func keepLargestBlob(_ image: CGImage, alphaThreshold: UInt8 = 32) -> CGImage? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        // 用 premultipliedLast (RGBA)：我们最后读 offset+3 拿 alpha。
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { return nil }
        let bytes = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        let n = width * height
        var componentID = [Int32](repeating: -1, count: n)
        var componentSize: [Int] = []
        var queue: [Int] = []
        queue.reserveCapacity(n / 4)

        // 遍历每个像素做 BFS 起点。已访问 / 透明的直接跳过。
        for start in 0..<n {
            if componentID[start] != -1 { continue }
            if bytes[start * bytesPerPixel + 3] < alphaThreshold { continue }

            let cid = Int32(componentSize.count)
            var size = 0
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            componentID[start] = cid
            var head = 0

            while head < queue.count {
                let idx = queue[head]; head += 1
                size += 1
                let x = idx % width
                let y = idx / width
                // 4-邻域够用：8-邻域会把只挨着对角线的两块当同一块，反而放走细连接。
                let neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                for (dx, dy) in neighbors {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                    let nidx = ny * width + nx
                    if componentID[nidx] != -1 { continue }
                    if bytes[nidx * bytesPerPixel + 3] < alphaThreshold { continue }
                    componentID[nidx] = cid
                    queue.append(nidx)
                }
            }
            componentSize.append(size)
        }

        guard let maxSize = componentSize.max(), maxSize > 0 else { return nil }
        let largestCID = Int32(componentSize.firstIndex(of: maxSize) ?? 0)

        // 非最大块的像素全部清 0（RGB 也清，避免预乘残色）
        for i in 0..<n {
            if componentID[i] != largestCID {
                bytes[i * bytesPerPixel] = 0
                bytes[i * bytesPerPixel + 1] = 0
                bytes[i * bytesPerPixel + 2] = 0
                bytes[i * bytesPerPixel + 3] = 0
            }
        }

        return context.makeImage()
    }

    // MARK: - 白描边

    /// 把 alpha 往外膨胀 radius 像素当作描边外边缘，填白色，再把原图 source-over 盖回去。
    /// 输出图会比输入大一圈 (radius × 2)，正好装下描边光晕，UI 端 scaledToFit 就自然带边。
    private static func addWhiteStroke(_ image: CGImage, radius: Double) -> CGImage? {
        let ci = CIImage(cgImage: image)

        // 1. 膨胀 alpha —— 得到描边的「外轮廓」形状。
        let dilated = ci.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])

        // 2. 用 CIColorMatrix 把 dilated 变成「同形状的纯白色板」：
        //    R/G/B 全靠 bias 给 1，A 沿用 dilated 的 alpha 通道。
        let whitePlate = dilated.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])

        // 3. 原图 source-over 到白板上。白板露在原图透明处 = 描边光晕。
        let composed = ci.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: whitePlate,
        ])

        // extent 用膨胀后的：包含向外的白描边光晕，不能拿原图 extent 截掉了。
        return sharedContext.createCGImage(composed, from: dilated.extent)
    }
}
