import SwiftUI
import RealityKit

/// 可拖动 360° 查看的静态 3D 模型（不自动播放动画）。
/// 松手后停在当前角度，只有重新进入这个页面才回正 —— 转到一半松个手就弹回去很难用。
/// 平平首页和狗朋友详情共用同一套手势和回正行为，别再各写一份。
struct Model3DView: View {
    let modelURL: URL

    /// 模型占画面多满（0–1）。按更紧的那条边算，所以给 0.95 就是「贴边还剩一点余量」。
    /// 各页构图不同：首页是独占的舞台要撑满，狗朋友详情是 Form 里的一行，留点边距不顶格。
    var fillRatio: Float = 0.8

    @State private var dragAngle: Double = 0
    @State private var committedAngle: Double = 0
    private static let pivotName = "pivot"

    /// 相机固定不动，改用缩放模型来适配画面 —— 比推拉相机好推算，也不受模型比例影响。
    private static let cameraDistance: Float = 1
    /// 视场角锁成「垂直」60°：默认的水平取向会让可见高度随控件宽高比变，没法算。
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

            // 相机距离 1、垂直视场 60° 时的可见范围。
            let visibleHeight = 2 * Self.cameraDistance
                * tan(Self.verticalFOVDegrees / 2 * .pi / 180)
            let visibleWidth = visibleHeight * aspect

            // 缩放到「填满画面」。以前是把最长边缩到 1，但狗的最长边是身长不是身高，
            // 那条边还有一截朝屏幕里根本看不见，所以画面里的狗只有六成高，
            // 相机推得再近也没用 —— 得按屏幕上真正占多大来算。
            //
            // 绕 Y 轴转的时候高度不变，横向轮廓在 x 和 z 之间来回变，
            // 所以横向按更宽的那个算，保证转到任何角度都不切边。
            let holder = Entity()
            holder.addChild(model)
            let bounds = model.visualBounds(relativeTo: holder)
            let horizontal = max(bounds.extents.x, bounds.extents.z)
            if bounds.extents.y > 0 && horizontal > 0 {
                model.position = -bounds.center
                let scale = min(visibleHeight / bounds.extents.y, visibleWidth / horizontal) * fillRatio
                holder.scale = SIMD3(repeating: scale)
            }

            // 单独包一层做旋转，这样缩放/居中和用户拖拽互不干扰。
            let pivot = Entity()
            pivot.name = Self.pivotName
            pivot.addChild(holder)
            content.add(pivot)

            // 显式放一台相机，不依赖 RealityView 的默认取景。
            var lens = PerspectiveCameraComponent()
            lens.fieldOfViewInDegrees = Self.verticalFOVDegrees
            lens.fieldOfViewOrientation = .vertical
            let camera = Entity()
            camera.components.set(lens)
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
