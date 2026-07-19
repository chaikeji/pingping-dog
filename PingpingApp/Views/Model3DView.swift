import SwiftUI
import RealityKit

/// 可拖动 360° 查看的静态 3D 模型（松手回正，不自动播放动画）。
/// 平平首页和狗朋友详情共用同一套手势和回正行为，别再各写一份。
struct Model3DView: View {
    let modelURL: URL

    @State private var dragAngle: Double = 0
    @State private var committedAngle: Double = 0

    /// 归一化之后模型最长边就是 1，相机退到这个距离刚好让它占画面大半。
    /// 60° 视场角下 1.4 约等于七成高度，留点边距不顶格。
    private static let cameraDistance: Float = 1.4
    private static let pivotName = "pivot"

    var body: some View {
        RealityView { content in
            guard let model = try? await ModelEntity(contentsOf: modelURL) else { return }

            // Tripo 出的 USDZ 是 Z-up，RealityKit 是 Y-up，直接塞进来相机是从头顶往下看（只看得到狗背）。
            // 绕 X 轴 -90° 把它扶正。QuickLook 会自己读坐标系声明，所以全屏是正的、这里不是。
            model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

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
                .onEnded { _ in
                    withAnimation(.spring) { dragAngle = 0 }  // 松手回正
                    committedAngle = 0
                }
        )
    }
}
