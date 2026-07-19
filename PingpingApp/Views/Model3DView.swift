import SwiftUI
import RealityKit

/// 可拖动 360° 查看的静态 3D 模型（松手回正，不自动播放动画）。
/// 平平首页和狗朋友详情共用同一套手势和回正行为，别再各写一份。
struct Model3DView: View {
    let modelURL: URL

    @State private var dragAngle: Double = 0
    @State private var committedAngle: Double = 0

    var body: some View {
        RealityView { content in
            guard let entity = try? await ModelEntity(contentsOf: modelURL) else { return }
            content.add(entity)
        } update: { content in
            content.entities.first?.transform.rotation =
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
