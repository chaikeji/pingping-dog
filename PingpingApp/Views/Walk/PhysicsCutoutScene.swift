import SwiftUI
import UIKit
import CoreMotion

/// [[MonthlyReviewGalleryView]] 的月卡背景：把当月的抠图贴纸从卡顶更高处**可见地**掉进来，
/// 走真物理 —— iOS 内置的 `UIDynamicAnimator` 挂 gravity + collision + itemBehavior，
/// 贴纸会掉、会撞、会转、会堆到卡底。
///
/// 关键设计：物理层的高度 = `cardHeight + spawnAboveHeight`，比卡片本身高，
/// 顶部那段是"卡上方的空气"，贴纸在这段路径里下落是**看得见**的（父视图不 clip）。
/// 碰撞边界只留左右下三边，顶部开放 —— 贴纸从上方 spawn 后自由掉进来，
/// 落到 y = 总高（= 卡底）就被 bottom boundary 拦住，弹几下堆起来。
///
/// 卡片 218pt × ~350pt 小区域，跑完 ~6 秒动画就把引擎停掉，剩下静态叠加图，
/// 免得整个画廊 12 张卡同时跑物理把电池吃干。
struct PhysicsCutoutScene: UIViewRepresentable {
    /// 当月已抠好的贴纸（老 route 补跑完 / 新遛狗后自动填进来）。
    let cutouts: [UIImage]
    /// 稳定随机种子：一般传 year * 100 + month，同一张卡每次进都长一样。
    let seed: Int
    /// 卡片视觉高度（用来算碰撞边界只在卡底）。
    let cardHeight: CGFloat
    /// 卡上方可见的"空气"高度：贴纸从这段的顶掉下来，下落可见。
    let spawnAboveHeight: CGFloat

    func makeUIView(context: Context) -> PhysicsCutoutHostView {
        let host = PhysicsCutoutHostView(
            seed: UInt64(seed),
            cardHeight: cardHeight,
            spawnAboveHeight: spawnAboveHeight
        )
        host.updateCutouts(cutouts)
        return host
    }

    func updateUIView(_ host: PhysicsCutoutHostView, context: Context) {
        // cutouts 数量涨了（补跑塞新贴纸进来）→ host 把新增的加进物理；
        // 数量没变 / 变少的场景不处理。
        host.updateCutouts(cutouts)
    }
}

/// 承载物理引擎的 UIView。之所以不用纯 SwiftUI：SwiftUI 没有内置的碰撞 / 重力，
/// 想要「贴纸互相撞开」这种效果只能走 UIKit 的 UIDynamicAnimator 或者 SpriteKit。
/// UIDynamicAnimator 上手最轻，物理感也够用，就它了。
final class PhysicsCutoutHostView: UIView {
    private let seed: UInt64
    private let cardHeight: CGFloat
    private let spawnAboveHeight: CGFloat
    private var rng: SeededRNG
    private lazy var animator = UIDynamicAnimator(referenceView: self)
    private let gravity: UIGravityBehavior = {
        let g = UIGravityBehavior()
        g.magnitude = 1.4 // 比默认 1.0 稍猛，卡片空间小、要它快点掉到底
        return g
    }()
    private let collision: UICollisionBehavior = {
        let c = UICollisionBehavior()
        c.translatesReferenceBoundsIntoBoundary = false // 我们自己设边界（只左右下，顶开放）
        return c
    }()
    private lazy var itemBehavior: UIDynamicItemBehavior = {
        let b = UIDynamicItemBehavior()
        b.elasticity = 0.35 // 有点弹，落地"咚"一下再定
        b.friction = 0.4
        b.resistance = 0.8 // 空气阻力大一点，才会真的停下来，不然一直微微滑
        // 角阻尼调高 —— 让贴纸落地不再继续打转，更容易正着停下（"少侧躺、少横着"）。
        b.angularResistance = 3.5
        // 每帧回调用来查"未落底名单"—— 名单空了才把重力交给 motion。
        // capture self weakly，view 释放后闭包不再触发。
        b.action = { [weak self] in self?.checkLandingProgress() }
        return b
    }()

    /// 已经上物理的贴纸数量 —— updateCutouts 靠这个判定"哪些是新增的"。
    private var placedCount = 0
    private var pendingCutouts: [UIImage] = []
    private var boundariesInstalled = false
    /// 还没进入卡片区域的贴纸。名单非空时 gravity 强制向下，不跟 motion。
    /// 空了才切给 motion.gravity —— 修的是"手机平放 motion 向量 ≈ 0、贴纸永远落不下来"这个 bug。
    /// 名单里的贴纸不吃"顶边兜底"，保证初次下落能穿过 y = spawnAboveHeight 落进卡内。
    private var unlandedItems: [UIImageView] = []
    /// 记录最新一次 motion 传来的重力方向，落底后立刻用；平放时长度接近 0，是预期的。
    private var latestMotionDx: Double = 0
    private var latestMotionDy: Double = 1.0 // 默认向下，MotionBroadcaster 还没喂数据前也能落

    /// 单张贴纸的目标高度。多了自动缩小避免堆爆。
    private let baseHeight: CGFloat = 52
    /// 卡片能装的最大贴纸数。多了性能扛不住，也堆得看不清。
    private let maxStickers = 24

    init(seed: UInt64, cardHeight: CGFloat, spawnAboveHeight: CGFloat) {
        self.seed = seed
        self.cardHeight = cardHeight
        self.spawnAboveHeight = spawnAboveHeight
        self.rng = SeededRNG(seed: seed)
        super.init(frame: .zero)
        clipsToBounds = false // 关键：贴纸能溢出到 view 外，别被裁
        isUserInteractionEnabled = false
        animator.addBehavior(gravity)
        animator.addBehavior(collision)
        animator.addBehavior(itemBehavior)
        // 注册到全局 motion 广播器：转手机时会调 updateGravity(dx:dy:) 改变重力方向。
        // Weak ref，view 释放不会泄漏。
        MotionBroadcaster.shared.register(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 由 [[MotionBroadcaster]] 调用，把当前设备的重力向量喂进 UIGravityBehavior。
    /// motion.gravity 是设备坐标系（x 右、y 上、z 出屏），我们转到屏幕坐标系（y 下）。
    /// 系数放大一点让贴纸真的滚动而不是佛系挪动。
    /// **只在贴纸都落底之后才应用 motion**：手机平放时 motion.gravity ≈ (0, 0, ±1)，
    /// x/y 都接近 0，直接灌进引擎会导致新 spawn 的贴纸卡在半空。
    func updateGravity(dx: Double, dy: Double) {
        latestMotionDx = dx
        latestMotionDy = dy
        applyGravityForCurrentState()
    }

    /// 未落底名单非空 → 强制向下（0, 1）；名单空 → 用 motion。
    /// spawn / 每帧检查 / 收到 motion 更新，三处都调这里，保证方向随时一致。
    private func applyGravityForCurrentState() {
        if unlandedItems.isEmpty {
            gravity.gravityDirection = CGVector(dx: latestMotionDx, dy: latestMotionDy)
        } else {
            gravity.gravityDirection = CGVector(dx: 0, dy: 1.0)
        }
    }

    /// itemBehavior.action 每帧回调触发。做两件事：
    /// 1. 把已经"进入卡内"的贴纸从未落底名单里移除；名单空后 applyGravityForCurrentState 切给 motion。
    /// 2. 已落底贴纸的"顶边软兜底"—— center.y 低于 spawnAboveHeight + halfH 就 clamp 回来 +
    ///    清掉上冲速度。取代真边界，避免 UICollisionBehavior 高速 tunneling 把贴纸永久挤到线上方。
    private func checkLandingProgress() {
        // 阶段 1：更新未落底名单
        if !unlandedItems.isEmpty {
            let before = unlandedItems.count
            unlandedItems.removeAll { $0.center.y >= spawnAboveHeight }
            if unlandedItems.count != before {
                applyGravityForCurrentState()
            }
        }

        // 阶段 2：已落底贴纸的顶边 clamp
        for item in itemBehavior.items {
            guard let iv = item as? UIImageView else { continue }
            // 还在初次下落的不管，让它自然穿过 spawnAboveHeight 落进卡内。
            if unlandedItems.contains(where: { $0 === iv }) { continue }
            let halfH = iv.bounds.height / 2
            let minCenterY = spawnAboveHeight + halfH
            guard iv.center.y < minCenterY else { continue }
            iv.center.y = minCenterY
            let vel = itemBehavior.linearVelocity(for: iv)
            if vel.y < 0 {
                // 上冲速度清零 —— addLinearVelocity 是叠加式，加 -vel.y 就把 y 分量抹平。
                itemBehavior.addLinearVelocity(CGPoint(x: 0, y: -vel.y), for: iv)
            }
            animator.updateItem(usingCurrentState: iv)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // bounds 第一次拿到真实值之前，别急着装边界或掉贴纸。
        guard bounds.width > 0, bounds.height > 0 else { return }

        if !boundariesInstalled {
            installBoundaries()
            boundariesInstalled = true
            dropPending()
        }
    }

    /// 三面墙：左、右、底。顶边不装真边界 —— 见 [[checkLandingProgress]]，
    /// 用每帧手工 clamp 兜底。原因：UICollisionBehavior 的线边界在高速运动下会 tunnel，
    /// 一旦贴纸跑到线上方就再也回不到卡内（线边界对称拦，从上方掉回来也会被弹回去，永远卡死）。
    private func installBoundaries() {
        collision.removeAllBoundaries()
        let w = bounds.width
        let h = bounds.height // 总高 = cardHeight + spawnAboveHeight
        collision.addBoundary(
            withIdentifier: "left" as NSString,
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 0, y: h)
        )
        collision.addBoundary(
            withIdentifier: "right" as NSString,
            from: CGPoint(x: w, y: 0),
            to: CGPoint(x: w, y: h)
        )
        collision.addBoundary(
            withIdentifier: "bottom" as NSString,
            from: CGPoint(x: 0, y: h),
            to: CGPoint(x: w, y: h)
        )
    }

    // MARK: - 对外

    func updateCutouts(_ cutouts: [UIImage]) {
        // 只关注新增：已经在物理里跑的不动，稳定的月份不会因为父视图 rebuild 就重新掉一遍。
        let capped = Array(cutouts.prefix(maxStickers))
        pendingCutouts = capped
        if boundariesInstalled { dropPending() }
    }

    private func dropPending() {
        guard pendingCutouts.count > placedCount else { return }
        let newOnes = Array(pendingCutouts.suffix(from: placedCount))
        for img in newOnes { spawn(img) }
        placedCount = pendingCutouts.count
        // 顶边不装真边界（见 [[installBoundaries]]），落底后靠 checkLandingProgress 每帧 clamp。
        // 不再有 6 秒 freeze —— 保留物理引擎，用户随时可以转手机让贴纸滚动。
        // UIDynamicAnimator 内部会在贴纸静止时自动降低更新频率，电池压力可控。
    }

    // MARK: - 一张贴纸的落生

    private func spawn(_ image: UIImage) {
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit

        // 贴纸目标高度，随数量收敛。maxStickers=24 时最小 ~34pt。
        let densityShrink = max(0, CGFloat(placedCount - 6)) * 0.9
        let h = max(34, baseHeight - densityShrink)
        let aspect = image.size.width / max(image.size.height, 1)
        let w = h * aspect
        iv.frame = CGRect(x: 0, y: 0, width: w, height: h)

        // 起点：**view 顶部 0-40pt 之间**（在 spawnAboveHeight 段内，视觉可见）。
        // 之前是 y = -h（在 view 外），用户看到的是"从卡顶冒出来"，现在改成看得见完整下落。
        let xRange = max(1, bounds.width - w)
        let startX = CGFloat.random(in: 0...xRange, using: &rng)
        let startY = CGFloat.random(in: 0...40, using: &rng) - h * 0.5
        iv.frame.origin = CGPoint(x: startX, y: startY)

        // 初始旋转很小（±5°）+ 极小角速度：想要"多数正着落"就得从起手就别转太狠。
        // 加上 itemBehavior.angularResistance = 3.5，几乎撞两下就停旋。
        let initialAngle = CGFloat.random(in: -0.08...0.08, using: &rng)
        iv.transform = CGAffineTransform(rotationAngle: initialAngle)

        addSubview(iv)
        gravity.addItem(iv)
        collision.addItem(iv)
        itemBehavior.addItem(iv)

        // 落生时给一点点线速度 + 极小角速度，弹跳自然、但不会转成侧躺。
        let vx = CGFloat.random(in: -25...25, using: &rng)
        itemBehavior.addLinearVelocity(CGPoint(x: vx, y: 0), for: iv)
        let angularVel = CGFloat.random(in: -0.3...0.3, using: &rng)
        itemBehavior.addAngularVelocity(angularVel, for: iv)

        // 加入未落底名单 + 立即把重力切回向下，保证手机平放也能掉下来。
        unlandedItems.append(iv)
        applyGravityForCurrentState()
    }
}

// MARK: - Motion broadcaster

/// 全局单例：管一个 `CMMotionManager`（Apple 建议整个 app 只有一个实例），
/// 把 device motion 更新分发给所有注册过的 [[PhysicsCutoutHostView]]。
///
/// 用 `NSHashTable.weakObjects()` 存监听者，view 销毁时自动移除，不用手动 unregister。
/// 没监听者时懒得启动 motion；有人注册就自动开。
final class MotionBroadcaster {
    static let shared = MotionBroadcaster()

    private let manager = CMMotionManager()
    private let listeners = NSHashTable<PhysicsCutoutHostView>.weakObjects()

    private init() {}

    func register(_ view: PhysicsCutoutHostView) {
        listeners.add(view)
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30Hz 够顺
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // motion.gravity 是设备坐标系（x 右、y 上、z 出屏），单位 g，长度 = 1。
            // 转屏幕坐标（y 下）：dx 保持，dy 取反。
            let dx = motion.gravity.x
            let dy = -motion.gravity.y
            for view in self.listeners.allObjects {
                view.updateGravity(dx: dx, dy: dy)
            }
        }
    }
}

// MARK: - 稳定随机数

/// SplitMix64：种子进去，同样的调用序列出来同样的数。
/// 用系统 Random 每次开都不一样，同一张月卡下场都不一样，看着乱。
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
