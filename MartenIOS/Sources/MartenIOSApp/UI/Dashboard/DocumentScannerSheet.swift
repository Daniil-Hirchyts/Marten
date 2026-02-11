import SwiftUI

#if canImport(UIKit) && canImport(VisionKit)
import UIKit
import VisionKit
#endif

struct DocumentScannerSheet: View {
    let onScannedPages: ([Data]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if canImport(UIKit) && canImport(VisionKit)
        if #available(iOS 13.0, *) {
            DocumentScannerRepresentable { pages in
                onScannedPages(pages)
                dismiss()
            } onCancel: {
                dismiss()
            }
            .ignoresSafeArea()
        } else {
            unsupportedView
        }
        #else
        unsupportedView
        #endif
    }

    private var unsupportedView: some View {
        NavigationStack {
            ContentUnavailableView(
                "Scanner Unavailable",
                systemImage: "doc.text.viewfinder",
                description: Text("Document scanning is only available on iOS with VisionKit support.")
            )
            .navigationTitle("Scan Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#if canImport(UIKit) && canImport(VisionKit)
@available(iOS 13.0, *)
private struct DocumentScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: ([Data]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanned: ([Data]) -> Void
        let onCancel: () -> Void

        init(onScanned: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onScanned = onScanned
            self.onCancel = onCancel
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [Data] = []
            pages.reserveCapacity(scan.pageCount)

            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                if let jpegData = image.jpegData(compressionQuality: 0.92) {
                    pages.append(jpegData)
                }
            }

            onScanned(pages)
        }
    }
}
#endif
