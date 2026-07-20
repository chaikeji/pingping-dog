import SwiftUI
import RealityKit

/// 可拖动 360° 查看的静态 3D 模型（不自动播放动画）。
/// 松手后停在当前角度，只有重新进入这个页面才回正 —— 转到一半松个手就弹回去很难用。
/// 平平首页和狗朋友详情共用同一套手势和回正行为，别再各写一份。
struct Model3DView: View {
    let modelURL: URL

    /// 怎么定模型在画面里的大小。**两种都保证不裁切** —— 画布边缘一旦切到模型，
    /// 就会露出一条硬邦邦的水平线，看着像个方框，很难看。
    enum Sizing {
        /// 高度优先：**留下来的那部分**高度 = 画布高度 × `heightRatio`。
        /// 万一横向会顶出去，再按 `maxWidthRatio` 收回来，两边留白。
        ///
        /// `bottomCrop` 是从底下切掉的比例（0 = 整只都露着）。切法不是砍网格，
        /// 而是把模型往下挪、让底部落到画布外面，画布下沿就成了裁切线。
        /// 引擎只认包围盒、不知道「袖子」在哪，所以只能用比例表达，真机上比着调。
        case fitHeight(heightRatio: Float, maxWidthRatio: Float, bottomCrop: Float)
        /// 按更紧的那条边等比塞进画布。狗朋友详情用的，已经调准了别动。
        case screenFill(ratio: Float)
    }

    /// **故意不给默认值**：给了默认值，就会出现「改一次默认值、没传参的页面跟着变」的事故。
    /// 这个 view 只有两个调用方，每个都必须自己写清楚要多大，各调各的互不影响。
    var sizing: Sizing

    @State private var dragAngle: Double = 0
    @State private var committedAngle: Double = 0
    private static let pivotName = "pivot"

    /// screenFill 模式下相机固定在这个距离，改用缩放模型来适配画面 —— 比推拉相机好推算。
    private static let fillCameraDistance: Float = 1
    /// screenFill 模式下把视场角锁成「垂直」60°：
    /// 默认的水平取向会让可见高度随控件宽高比变，没法算。
    private static let verticalFOVDegrees: Float = 60

    /// 摆正模型的初始姿态。两步，调的时候分清楚是哪一步不对：
    ///
    /// - 绕 X 轴 -90°：Tripo 的 USDZ 是 Z-up、RealityKit 是 Y-up，不转的话相机是从头顶往下看。
    ///   要是效果变成倒立或者朝另一边躺，就是这个角度的正负号反了。
    /// - 绕 Y 轴 -90°：扶正之后狗头朝屏幕右方（+X），转过来正对镜头（+Z）。
    ///   要是变成屁股对着你，就是这个角度的正负号反了。
    private static let uprightOrientation: simd_quatf =
        simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]) * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

    var body: some View {
        // 要按画面比例算缩放，就得知道控件多宽多高。
        GeometryReader { geo in
            stage(aspect: Float(geo.size.width / max(geo.size.height, 1)))
        }
    }

    private func stage(aspect: Float) -> some View {
        RealityView { content in
            guard let model = try? await ModelEntity(contentsOf: modelURL) else { return }

            model.orientation = Self.uprightOrientation

            let holder = Entity()
            holder.addChild(model)
            let bounds = model.visualBounds(relativeTo: holder)
            model.position = -bounds.center

            // 画布在世界坐标里的可见范围。相机固定不动，缩放模型去适配。
            let distance = Self.fillCameraDistance
            let visibleHeight = 2 * distance * tan(Self.verticalFOVDegrees / 2 * .pi / 180)
            let visibleWidth = visibleHeight * aspect

            // 绕 Y 轴转的时候高度不变，横向轮廓在 x 和 z 之间来回变，
            // 所以横向一律按更宽的那个算 —— 保证转到任何角度都不会突然顶出去。
            let horizontal = max(bounds.extents.x, bounds.extents.z)
            // 裁切要靠把模型整体下移来实现，所以缩放和位移得一起算出来。
            var verticalOffset: Float = 0
            if bounds.extents.y > 0 && horizontal > 0 {
                let scale: Float
                switch sizing {
                case .fitHeight(let heightRatio, let maxWidthRatio, let bottomCrop):
                    // heightRatio 说的是「留下来那部分」占画布多高，所以先按保留比例
                    // 反推整只模型该多大 —— 切得越多，整只就得放得越大。
                    let keep = max(1 - bottomCrop, 0.05)
                    let byHeight = visibleHeight * heightRatio / (keep * bounds.extents.y)
                    let byWidth = visibleWidth * maxWidthRatio / horizontal
                    scale = min(byHeight, byWidth)  // 宽度那条是保险，正常不触发
                    // 把裁切线对齐到画布下沿：切掉的部分正好落在画布外面。
                    let modelHeight = bounds.extents.y * scale
                    verticalOffset = -visibleHeight / 2 + modelHeight * (0.5 - bottomCrop)
                case .screenFill(let ratio):
                    scale = min(visibleHeight / bounds.extents.y, visibleWidth / horizontal) * ratio
                }
                holder.scale = SIMD3(repeating: scale)
            }

            var lens = PerspectiveCameraComponent()
            lens.fieldOfViewInDegrees = Self.verticalFOVDegrees
            lens.fieldOfViewOrientation = .vertical

            // 单独包一层做旋转，这样缩放/居中和用户拖拽互不干扰。
            // 位移挂在 pivot 上：绕 Y 轴转不改变高度，所以拖动时裁切线纹丝不动。
            let pivot = Entity()
            pivot.name = Self.pivotName
            pivot.position.y = verticalOffset
            pivot.addChild(holder)
            content.add(pivot)

            // 显式放一台相机，不依赖 RealityView 的默认取景。
            let camera = Entity()
            camera.components.set(lens)
            camera.position = [0, 0, distance]
            content.add(camera)
        } update: { content in
            content.entities.first { $0.name == Self.pivotName }?.transform.rotation =
                simd_quatf(angle: Float(Angle(degrees: dragAngle).radians), axis: [0, 1, 0])
        }
        .gesture(
            DragGesture()
                .onChanged { dragAngle = committedAngle + $0.translation.width * 0.6 }
                .onEnded { _ in committedAngle = dragAngle }  // 停在松手时的角度
        )
        // 回正放在这里而不是靠视图销毁：首页那个是常驻 tab，切走再切回来不会重建，
        // 只有 onAppear 能保证「每次进这一页都是正脸」对导航和 tab 切换都成立。
        .onAppear {
            dragAngle = 0
            committedAngle = 0
        }
    }
}
