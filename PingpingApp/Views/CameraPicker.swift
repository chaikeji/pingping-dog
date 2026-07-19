import SwiftUI
import UIKit
import PhotosUI

/// 相机拍照封装（UIImagePickerController，sourceType = .camera）。
/// 仅在有相机的真机上可用（模拟器无相机，调用方需先判断 `isCameraAvailable`）。
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

extension UIImage {
    /// 压成适合上传的 JPEG：长边最多 `maxDimension`，再按 `quality` 编码。
    /// 相机原图是 12MP、编出来 3~8MB，在国内移动网络上传经常卡到超时；
    /// 而 Tripo 单图建模并不需要这个分辨率，1600px 长边足够，体积能降到几百 KB。
    func uploadJPEGData(maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return nil }

        // 只缩不放：本来就小于上限的图保持原样，避免糊掉。
        let scale = min(1, maxDimension / longEdge)
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1          // 按像素出图，别再乘一遍屏幕 scale
        format.opaque = true      // 照片没有透明通道
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// 统一的「拍照 / 从相册选」选择流程。绑定一个 Bool 触发弹窗，选好后回调 JPEG Data。
/// 相册原图常是 HEIC，这里统一转成 JPEG 再回调，兼容 Tripo（只收 JPEG/PNG）。
private struct PhotoSourcePicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPicked: (Data) -> Void

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("添加照片", isPresented: $isPresented, titleVisibility: .visible) {
                if CameraPicker.isCameraAvailable {
                    Button("拍照") { showCamera = true }
                }
                Button("从相册选") { showLibrary = true }
                Button("取消", role: .cancel) {}
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let jpeg = image.uploadJPEGData() { onPicked(jpeg) }
                }
                .ignoresSafeArea()
            }
            .task(id: libraryItem) {
                guard let libraryItem, let raw = try? await libraryItem.loadTransferable(type: Data.self) else { return }
                if let ui = UIImage(data: raw), let jpeg = ui.uploadJPEGData() {
                    onPicked(jpeg)
                }
                self.libraryItem = nil
            }
    }
}

extension View {
    /// 点一个按钮把 `isPresented` 置 true，即弹「拍照 / 从相册选」，选好回调 JPEG Data。
    func photoSourcePicker(isPresented: Binding<Bool>, onPicked: @escaping (Data) -> Void) -> some View {
        modifier(PhotoSourcePicker(isPresented: isPresented, onPicked: onPicked))
    }
}
