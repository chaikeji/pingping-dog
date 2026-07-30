import UIKit
import Vision

/// 打分一张照片有多合适当「贴纸封面」：主体是狗或猫、够大、够居中、画面里没大人（= 大概率没牵绳）。
/// 全本地跑（Vision 框架），不花钱。分数越大越合适，0 = 不合适 / 里面没猫狗 / 跑挂了。
///
/// 用法：[[WalkSessionViewModel]] finish() 时把每张照片打一遍分存进 WalkRoute.photoScores，
/// 再挑 argmax 那张送 [[BackgroundRemovalService]] 抠图。上层不用理解分数含义，只比较大小。
enum PhotoQualityScorer {

    /// 打分算法版本。改逻辑（加新类别、调门槛、换公式）就加 1，
    /// [[PhotoCutoutPipeline]] 会拿这个跟 route.photoScorerVersion 对比，不一致就重跑。
    /// - v1：只识别 Dog
    /// - v2：Dog + Cat 都认
    /// - v3：门槛放宽 —— 用户反馈很多有猫狗但打分被拒的日子拿不到贴纸。
    ///       conf 0.5→0.35，area 0.05→0.02，final gate 0.1→0.03。
    static let currentVersion = 3

    /// JPEG/HEIC/PNG 原图 Data。跑挂 / 没猫狗 都回 0。
    static func score(imageData: Data) -> Double {
        guard let cg = UIImage(data: imageData)?.cgImage else { return 0 }
        return score(cgImage: cg)
    }

    static func score(cgImage: CGImage) -> Double {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let animalRequest = VNRecognizeAnimalsRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()

        // 一次跑两个 request，共用同一份图 handler，比分两次跑省一半 IO。
        do { try handler.perform([animalRequest, humanRequest]) } catch { return 0 }

        // 挑置信度最高那只「猫或狗」。identifier 是 "Dog" / "Cat"，两个都收。
        var animalArea = 0.0
        var animalConf = 0.0
        var animalOffCenter = 0.0
        if let obs = animalRequest.results {
            let animals: [(bbox: CGRect, conf: Float)] = obs.compactMap { o in
                guard let l = o.labels.first(where: { $0.identifier == "Dog" || $0.identifier == "Cat" }) else { return nil }
                return (o.boundingBox, l.confidence)
            }
            if let best = animals.max(by: { $0.conf < $1.conf }) {
                animalArea = Double(best.bbox.width * best.bbox.height)
                animalConf = Double(best.conf)
                let cx = Double(best.bbox.midX)
                let cy = Double(best.bbox.midY)
                // 到图中心 (0.5, 0.5) 的欧氏距，最远 ≈ 0.707。
                animalOffCenter = sqrt(pow(cx - 0.5, 2) + pow(cy - 0.5, 2))
            }
        }

        // 门槛：v3 放宽 —— conf 0.35（原 0.5）、area 0.02（原 0.05）。
        // 之前太严，中距离 / 侧影 / 半只狗都被判 0，一整天的照片没一张能生贴纸。
        // 现在只挡真的完全没动物 / 太糊的极端情况。
        guard animalConf > 0.35, animalArea > 0.02 else { return 0 }

        // 人的信号：出现大面积的人 = 大概率是主人牵着 = 大概率带狗绳，罚分。
        var humanArea = 0.0
        if let humans = humanRequest.results {
            humanArea = humans.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
        }

        // 组合分。系数拍脑袋定的，跑一段真实数据再回来调。
        let base = animalArea * animalConf
        let centerPenalty = animalOffCenter * 0.3
        let humanPenalty = humanArea * 0.4
        return max(0, base - centerPenalty - humanPenalty)
    }

    /// 批量打分：返回跟输入一一对应的分数数组。任何一张挂了给 0，不中断其它。
    static func score(all datas: [Data]) -> [Double] {
        datas.map { score(imageData: $0) }
    }
}
