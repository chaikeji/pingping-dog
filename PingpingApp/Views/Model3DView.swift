import SwiftUI
import RealityKit

/// 可拖动 360° 查看的静态 3D 模型（不自动播放动画）。
/// 松手后停在当前角度，只有重新进入这个页面才回正 —— 转到一半松个手就弹回去很难用。
/// 平平首页和狗朋友详情共用同一套手势和回正行为，别再各写一份。
struct Model3DView: View {
    let modelURL: URL

    @State private var dragAngle: Double = 0
    @State private var committedAngle: Double = 0

    /// 归一化之后模型最长边就是 1，相机退到这个距离刚好让它占画面大半。
    /// 60° 视场角下 1.4 约等于七成高度，留点边距不顶格。
    private static let cameraDistance: Float = 1.4
    private static let pivotName = "pivot"

    /// 摆正模型的初始姿态。两步，调的时候分清楚是哪一步不对：
    ///
    /// - 绕 X 轴 -90°：Tripo 的 USDZ 是 Z-up、RealityKit 是 Y-up，不转的话相机是从头顶往下看。
    ///   要是效果变成倒立或者朝另一边躺，就是这个角度的正负号反了。
    /// - 绕 Y 轴 -90°：扶正之后狗头朝屏幕右方（+X），转过来正对镜头（+Z）。
    ///   要是变成屁股对着你，就是这个角度的正负号反了。
    private static let uprightOrientation: simd_quatf =
        simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]) * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

    var body: some View {
        RealityView { content in
            guard let model = try? await ModelEntity(contentsOf: modelURL) else { return }

            model.orientation = Self.uprightOrientation

            // 尺寸归一化：模型实际大小不固定，按包围盒缩到最长边为 1 并居中。
            // 不做这步就得靠 RealityView 的默认取景碰运气，之前小得像颗豆子就是这个原因。
            let holder = Entity()
            holder.addChild(model)
            let bounds = model.visualBounds(relativeTo: holder)
            let extent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            if extent > 0 {
                model.position = -bounds.center
                holder.scale = SIMD3(repeating: 1 / extent)
            }

            // 单独包一层做旋转，这样缩放/居中和用户拖拽互不干扰。
            let pivot = Entity()
            pivot.name = Self.pivotName
            pivot.addChild(holder)
            content.add(pivot)

            // 显式放一台相机，不依赖 RealityView 的默认取景。
            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent())
            camera.position = [0, 0, Self.cameraDistance]
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
