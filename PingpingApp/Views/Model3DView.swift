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
                .onEnded { _ in
                    withAnimation(.spring) { dragAngle = 0 }  // 松手回正
                    committedAngle = 0
                }
        )
    }
}

/// 全屏查看。刻意不用 QuickLook：它的初始视角由系统决定、改不了，
/// 会出现「内嵌是正脸、全屏是侧面」的不一致。用同一个 Model3DView 才能保证两边朝向一样。
struct Model3DFullScreenView: View {
    let modelURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground).ignoresSafeArea()
            Model3DView(modelURL: modelURL)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}
