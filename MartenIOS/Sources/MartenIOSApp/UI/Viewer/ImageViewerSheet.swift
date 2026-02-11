import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias ViewerImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias ViewerImage = NSImage
#endif

struct ImageViewerSheet: View {
    let item: ClipItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: ViewerImage?
    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.94).ignoresSafeArea()

                #if canImport(UIKit) || canImport(AppKit)
                if let image {
                    imageView(image)
                } else {
                    ProgressView()
                        .tint(.white)
                }
                #else
                ContentUnavailableView(
                    "Image Viewer Unavailable",
                    systemImage: "photo",
                    description: Text("This viewer is only available on iOS/macOS.")
                )
                #endif
            }
            .navigationTitle("Image")
            .imageViewerTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            baseScale = 1
                            baseOffset = .zero
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(.white)
                }
            }
            .task(id: item.objectID) {
                await loadImage()
            }
            .accessibilityLabel(item.primaryText ?? "Image")
            .accessibilityHint("Pinch to zoom, drag to pan, double tap to reset")
        }
    }

    #if canImport(UIKit) || canImport(AppKit)
    @ViewBuilder
    private func imageView(_ image: ViewerImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(baseScale * gestureScale)
            .offset(baseOffset + gestureOffset)
            .gesture(combinedGestures)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    baseScale = 1
                    baseOffset = .zero
                }
            }
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(baseScale * gestureScale)
            .offset(baseOffset + gestureOffset)
            .gesture(combinedGestures)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    baseScale = 1
                    baseOffset = .zero
                }
            }
        #endif
    }

    private var combinedGestures: some Gesture {
        SimultaneousGesture(magnificationGesture, dragGesture)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                baseScale = max(1, min(baseScale * value, 8))
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                baseOffset = baseOffset + value.translation
            }
    }
    #endif

    private func loadImage() async {
        image = await ImageThumbnailLoader.shared.loadThumbnail(for: item, maxPixelSize: 2_048)
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }
}

#if !os(iOS)
private extension View {
    func imageViewerTitleDisplayMode() -> some View { self }
}
#else
private extension View {
    func imageViewerTitleDisplayMode() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }
}
#endif
