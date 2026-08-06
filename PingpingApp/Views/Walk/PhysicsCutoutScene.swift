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
    /// 进入二层页面后明确暂停后台物理和传感器；返回本页再恢复。
    let isActive: Bool

    func makeUIView(context: Context) -> PhysicsCutoutHostView {
        let host = PhysicsCutoutHostView(
            seed: UInt64(seed),
            cardHeight: cardHeight,
            spawnAboveHeight: spawnAboveHeight
        )
        host.updateCutouts(cutouts)
        host.setActive(isActive)
        return host
    }

    func updateUIView(_ host: PhysicsCutoutHostView, context: Context) {
        // cutouts 数量涨了（补跑塞新贴纸进来）→ host 把新增的加进物理；
        // 数量没变 / 变少的场景不处理。
        host.updateCutouts(cutouts)
        host.setActive(isActive)
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
        g.gravityDirection = CGVector(dx: 0, dy: 1) // 永久向下 baseline，motion 只加侧向偏置
        return g
    }()
    private let collision: UICollisionBehavior = {
        let c = UICollisionBehavior()
        c.translatesReferenceBoundsIntoBoundary = false // 我们自己设四边边界，支持贴纸随重力上下移动
        return c
    }()
    private let itemBehavior: UIDynamicItemBehavior = {
        let b = UIDynamicItemBehavior()
        b.elasticity = 0.35 // 有点弹，落地"咚"一下再定
        b.friction = 0.4
        b.resistance = 0.8 // 空气阻力大一点，才会真的停下来，不然一直微微滑
        // 角阻尼调高 —— 让贴纸落地不再继续打转，更容易正着停下（"少侧躺、少横着"）。
        b.angularResistance = 3.5
        // **没有 action 每帧回调**。原来那版用 action 每帧遍历所有 item + O(N²) 名单查找 +
        // 顶边 clamp 触发 animator.updateItem —— 就是"贴纸碰卡片上沿卡一下瞬移到卡底"的元凶：
        // 主线程被这坨每帧工作堵住 → 物理引擎下一帧的 dt 暴涨到几百毫秒 → 位置直接跳 100+ pt。
        // 顶边根本不需要防御：elasticity=0.35 + resistance=0.8 算下来弹跳峰值 ~44pt，
        // 卡底反弹永远够不到 spawnAboveHeight = 180，clamp 从来没真正拦住过东西。
        return b
    }()

    /// 已经上物理的贴纸数量 —— updateCutouts 靠这个判定"哪些是新增的"。
    private var placedCount = 0
    private var pendingCutouts: [UIImage] = []
    private var boundariesInstalled = false
    private var containmentTopInstalled = false
    private var containmentTask: DispatchWorkItem?
    /// 记录最新一次 motion 传来的重力方向；小幅手抖会过滤，真实上下方向完整保留。
    private var latestMotionDx: Double = 0
    private var latestMotionDy: Double = 1.0 // 默认向下，MotionBroadcaster 还没喂数据前也能落
    /// 是否已经在监听全局 motion。didMoveToWindow 里切换：出栈/被隐藏时反注册，回到窗口再注册。
    private var isRegisteredForMotion = false
    private var shouldBeActive = true

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
        // 注册留给 didMoveToWindow —— 卡不在窗口里就没必要监听 motion，
        // 免得画廊页整个 12 张卡各自一份 motion callback 灌进空气。
    }

    required init?(coder: NSCoder) { fatalError() }

    /// SwiftUI LazyVStack 里被滚出屏 → window 变 nil → 反注册 motion，
    /// 滚回来 → window 有值 → 重新注册。全局广播器在监听者变空时会顺手关掉 CoreMotion。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateMotionRegistration()
    }

    /// 由 [[MotionBroadcaster]] 调用，把当前设备的重力向量喂进 UIGravityBehavior。
    /// motion.gravity 是设备坐标系（x 右、y 上、z 出屏），我们转到屏幕坐标系（y 下）。
    ///
    /// **dy clamp 到 ≥ 0.4**：手机平放时 motion 传来的 dy ≈ 0，直接灌就贴纸浮空；
    /// 给个下限保证一直有下落力。dx 缩一半：微微倾斜不至于横着滚开。
    ///
    /// **过滤 < 0.03（~1.7°）的抖动**：手持震颤会让 motion.gravity 在小范围内一直抖，
    /// 每次都喂进引擎 → 引擎永远醒着 → CPU 白烧 + 手机发烫。真挪动手机才更新。
    func updateGravity(dx: Double, dy: Double) {
        // 首次掉落统一使用固定向下重力，避免不同月份因手机当时角度不同而手感不一致。
        guard containmentTopInstalled else { return }
        // 保留真实上下方向；小幅手抖归零。旧代码 max(dy, 0.4) 会永远强制向下。
        let effectiveDy = abs(dy) < 0.08 ? 0 : dy
        let dxDiff = abs(dx - latestMotionDx)
        let dyDiff = abs(effectiveDy - latestMotionDy)
        guard dxDiff > 0.03 || dyDiff > 0.03 else { return }
        latestMotionDx = dx
        latestMotionDy = effectiveDy
        gravity.gravityDirection = CGVector(dx: dx * 0.5, dy: effectiveDy)
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

    /// 首次掉落只装左、右、底三面墙；等全部贴纸落入卡片后，再在卡片真实顶部封口。
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

    func setActive(_ active: Bool) {
        guard shouldBeActive != active else { return }
        shouldBeActive = active
        if active {
            if animator.behaviors.isEmpty {
                animator.addBehavior(gravity)
                animator.addBehavior(collision)
                animator.addBehavior(itemBehavior)
            }
        } else {
            animator.removeAllBehaviors()
        }
        updateMotionRegistration()
    }

    private func updateMotionRegistration() {
        // 贴纸全部落进卡片、封好上边界后才需要设备重力。
        let needsMotion = shouldBeActive && containmentTopInstalled && window != nil
        if needsMotion, !isRegisteredForMotion {
            MotionBroadcaster.shared.register(self)
            isRegisteredForMotion = true
        } else if !needsMotion, isRegisteredForMotion {
            MotionBroadcaster.shared.unregister(self)
            isRegisteredForMotion = false
        }
    }

    private func dropPending() {
        guard pendingCutouts.count > placedCount else { return }
        let previousCount = placedCount
        let newOnes = Array(pendingCutouts.suffix(from: placedCount))
        SessionEventLog.log(
            "perf.physics.batch",
            context: "monthSeed=\(seed), kind=\(previousCount == 0 ? "initial" : "append"), previous=\(previousCount), incoming=\(pendingCutouts.count), new=\(newOnes.count)"
        )

        // 补入新贴纸时重新打开卡片顶部；否则新贴纸会撞在卡片外侧。
        containmentTask?.cancel()
        if containmentTopInstalled {
            collision.removeBoundary(withIdentifier: "card-top" as NSString)
            containmentTopInstalled = false
        }
        gravity.gravityDirection = CGVector(dx: 0, dy: 1)
        updateMotionRegistration()
        // 提前推进 placedCount：stagger 期间如果 updateCutouts 又被叫，
        // 不能把这批 in-flight 的贴纸再算一遍。
        placedCount = pendingCutouts.count
        // 首次入场用 30ms 连续投放，避免肉眼看成前后两批；后续真实新增仍保留 60ms 降峰值。
        let spawnInterval = previousCount == 0 ? 0.03 : 0.06
        // 错峰入场：一次 addItem N 个物体会让 UIDynamicAnimator 头几帧算爆，
        // 主线程被挤 → 掉落卡顿。分帧后 CPU 摊平，视觉上也更像"一片片飘下来"。
        // [weak self]：view 被回收（LazyVStack 滚出屏 + dealloc）后剩余闭包直接 no-op。
        for (i, img) in newOnes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * spawnInterval) { [weak self] in
                self?.spawn(img)
            }
        }
        let lastSpawnDelay = Double(max(0, newOnes.count - 1)) * spawnInterval
        let task = DispatchWorkItem { [weak self] in
            self?.installCardTopBoundary()
        }
        containmentTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + lastSpawnDelay + 1.6, execute: task)
        // 保留物理引擎不 freeze —— 用户转手机贴纸会滚动。
        // UIDynamicAnimator 内部在所有 item 静止时自动进入 idle，电池压力可控。
    }

    /// 在卡片真实顶部封口。封口前把仍停在标题区的物体送回卡内，修复贴纸卡在月份标签上的情况。
    private func installCardTopBoundary() {
        guard bounds.width > 0 else { return }
        let topY = spawnAboveHeight
        for view in subviews where view.frame.minY < topY {
            view.frame.origin.y = topY + 1
            animator.updateItem(usingCurrentState: view)
        }
        collision.removeBoundary(withIdentifier: "card-top" as NSString)
        collision.addBoundary(
            withIdentifier: "card-top" as NSString,
            from: CGPoint(x: 0, y: topY),
            to: CGPoint(x: bounds.width, y: topY)
        )
        containmentTopInstalled = true
        updateMotionRegistration()
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
        let startY = CGFloat.random(in: 2...40, using: &rng)
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
    }
}

// MARK: - Motion broadcaster

/// 全局单例：管一个 `CMMotionManager`（Apple 建议整个 app 只有一个实例），
/// 把 device motion 更新分发给所有注册过的 [[PhysicsCutoutHostView]]。
///
/// 用 `NSHashTable.weakObjects()` 存监听者，view 销毁时自动移除；不过 SwiftUI 里
/// LazyVStack 可能长时间持有 offscreen view，所以每个 view 也在 didMoveToWindow(nil) 里
/// 主动 unregister，触发 CoreMotion 关掉传感器。
final class MotionBroadcaster {
    static let shared = MotionBroadcaster()

    private let manager = CMMotionManager()
    private let listeners = NSHashTable<PhysicsCutoutHostView>.weakObjects()

    private init() {}

    func register(_ view: PhysicsCutoutHostView) {
        listeners.add(view)
        startIfNeeded()
    }

    func unregister(_ view: PhysicsCutoutHostView) {
        listeners.remove(view)
        stopIfNeeded()
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

    /// 监听者名单空了就关掉传感器 —— accelerometer / gyroscope / magnetometer 三路
    /// 一直采样是明显耗电项，画廊/日历离开视野后必须停。
    private func stopIfNeeded() {
        guard manager.isDeviceMotionActive, listeners.allObjects.isEmpty else { return }
        manager.stopDeviceMotionUpdates()
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
