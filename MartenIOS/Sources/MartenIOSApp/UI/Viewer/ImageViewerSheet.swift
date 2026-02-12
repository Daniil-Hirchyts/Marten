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
    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                #if canImport(UIKit) || canImport(AppKit)
                if let image {
                    imageView(image)
                        .transition(.opacity)
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
            #if os(iOS)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }

                ToolbarItem(placement: .primaryAction) {
                    #if canImport(UIKit)
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(
                                item.primaryText ?? "Image",
                                image: Image(uiImage: image)
                            )
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .foregroundStyle(.white)
                    }
                    #endif
                }
            }
            .task(id: item.objectID) {
                await loadImage()
            }
            .accessibilityLabel(item.primaryText ?? "Image")
            .accessibilityHint("Pinch to zoom, double tap to reset zoom")
        }
    }

    #if canImport(UIKit) || canImport(AppKit)
    @ViewBuilder
    private func imageView(_ image: ViewerImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale * gestureScale)
            .gesture(magnificationGesture)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    scale = scale > 1 ? 1 : 2.5
                }
            }
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale * gestureScale)
            .gesture(magnificationGesture)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    scale = scale > 1 ? 1 : 2.5
                }
            }
        #endif
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                scale = max(1, min(scale * value, 8))
            }
    }
    #endif

    private func loadImage() async {
        image = await ImageThumbnailLoader.shared.loadThumbnail(for: item, maxPixelSize: 2_048)
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
