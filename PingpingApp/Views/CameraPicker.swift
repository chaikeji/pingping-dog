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
                    if let jpeg = image.jpegData(compressionQuality: 0.85) { onPicked(jpeg) }
                }
                .ignoresSafeArea()
            }
            .task(id: libraryItem) {
                guard let libraryItem, let raw = try? await libraryItem.loadTransferable(type: Data.self) else { return }
                if let ui = UIImage(data: raw), let jpeg = ui.jpegData(compressionQuality: 0.85) {
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
