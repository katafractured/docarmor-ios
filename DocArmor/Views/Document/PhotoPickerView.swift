import SwiftUI
import PhotosUI

/// Wraps `PHPickerViewController` for multi-image selection from the photo library.
struct PhotoPickerView: UIViewControllerRepresentable {
    let onCompletion: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10
        config.filter = .images
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onCompletion: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onCompletion: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onCompletion = onCompletion
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onCancel()
                return
            }

            // Use an actor-isolated container to prevent data races when multiple
            // loadObject callbacks complete concurrently on arbitrary threads.
            let count = results.count
            var ordered = [Int: UIImage](minimumCapacity: count)
            let lock = NSLock()
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        lock.withLock { ordered[index] = image }
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                // Preserve selection order regardless of callback completion order
                let images = (0..<count).compactMap { ordered[$0] }
                self?.onCompletion(images)
            }
        }
    }
}
