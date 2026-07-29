import UIKit
import Vision

/// 打分一张照片有多合适当「贴纸封面」：狗是主体、狗大、狗居中、画面里没大人（= 大概率没狗绳）。
/// 全本地跑（Vision 框架），不花钱。分数越大越合适，0 = 不合适 / 里面没狗 / 跑挂了。
///
/// 用法：[[WalkSessionViewModel]] finish() 时把每张照片打一遍分存进 WalkRoute.photoScores，
/// 再挑 argmax 那张送 [[BackgroundRemovalService]] 抠图。上层不用理解分数含义，只比较大小。
enum PhotoQualityScorer {

    /// JPEG/HEIC/PNG 原图 Data。跑挂 / 没狗 都回 0。
    static func score(imageData: Data) -> Double {
        guard let cg = UIImage(data: imageData)?.cgImage else { return 0 }
        return score(cgImage: cg)
    }

    static func score(cgImage: CGImage) -> Double {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let dogRequest = VNRecognizeAnimalsRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()

        // 一次跑两个 request，共用同一份图 handler，比分两次跑省一半 IO。
        do { try handler.perform([dogRequest, humanRequest]) } catch { return 0 }

        // 挑置信度最高那只「狗」。identifier 是 "Dog" / "Cat"，我们只认狗。
        var dogArea = 0.0
        var dogConf = 0.0
        var dogOffCenter = 0.0
        if let obs = dogRequest.results {
            let dogs: [(bbox: CGRect, conf: Float)] = obs.compactMap { o in
                guard let l = o.labels.first(where: { $0.identifier == "Dog" }) else { return nil }
                return (o.boundingBox, l.confidence)
            }
            if let best = dogs.max(by: { $0.conf < $1.conf }) {
                dogArea = Double(best.bbox.width * best.bbox.height)
                dogConf = Double(best.conf)
                let cx = Double(best.bbox.midX)
                let cy = Double(best.bbox.midY)
                // 到图中心 (0.5, 0.5) 的欧氏距，最远 ≈ 0.707。
                dogOffCenter = sqrt(pow(cx - 0.5, 2) + pow(cy - 0.5, 2))
            }
        }

        // 门槛：置信度太低（认错东西）或狗太小（远景剪影）—— 直接判 0，不进入排名。
        guard dogConf > 0.5, dogArea > 0.05 else { return 0 }

        // 人的信号：出现大面积的人 = 大概率是主人牵着 = 大概率带狗绳，罚分。
        var humanArea = 0.0
        if let humans = humanRequest.results {
            humanArea = humans.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
        }

        // 组合分。系数拍脑袋定的，跑一段真实数据再回来调。
        let base = dogArea * dogConf
        let centerPenalty = dogOffCenter * 0.3
        let humanPenalty = humanArea * 0.4
        return max(0, base - centerPenalty - humanPenalty)
    }

    /// 批量打分：返回跟输入一一对应的分数数组。任何一张挂了给 0，不中断其它。
    static func score(all datas: [Data]) -> [Double] {
        datas.map { score(imageData: $0) }
    }
}
