import CoreData
import CoreGraphics
import MartenCore
import SwiftUI

#if canImport(UIKit)
import CoreImage
import UIKit
private typealias ViewerImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias ViewerImage = NSImage
#endif

enum ImageViewerMode {
    case preview
    case edit
}

struct ImageViewerSheet: View {
    @ObservedObject var item: ClipItem
    var mode: ImageViewerMode = .preview
    var onEdit: (() -> Void)? = nil
    var onSaveEdits: ((Data) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var image: ViewerImage?
    @State private var editedImage: ViewerImage?
    @State private var didEditImage = false
    /// Incremented when a related representation changes so the image task re-fires.
    @State private var imageRepVersion: Int = 0

    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    TransparencyGrid(squareSize: 14)

                    Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08)

                    #if canImport(UIKit) || canImport(AppKit)
                    if let displayedImage {
                        imageView(displayedImage)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .tint(.primary)
                    }
                    #else
                    ContentUnavailableView(
                        "Image Viewer Unavailable",
                        systemImage: "photo",
                        description: Text("This viewer is only available on iOS/macOS.")
                    )
                    #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    updateViewportSize(proxy.size)
                }
                .onChange(of: proxy.size) { _, newValue in
                    updateViewportSize(newValue)
                }
            }
            .navigationTitle(mode == .edit ? "Edit Image" : "Image")
            .imageViewerTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        handleDone()
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if mode == .preview, let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }

                    #if canImport(UIKit)
                    if mode == .preview, let displayedImage {
                        ShareLink(
                            item: Image(uiImage: displayedImage),
                            preview: SharePreview(
                                item.primaryText ?? "Image",
                                image: Image(uiImage: displayedImage)
                            )
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    #endif
                }
            }
            .safeAreaInset(edge: .bottom) {
                if mode == .edit {
                    editControlsBar
                }
            }
            .task(id: imageTaskID) {
                await loadImage()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSManagedObjectContext.didMergeChangesObjectIDsNotification
                )
            ) { notification in
                // objectWillChange fires only for the ClipItem itself, not its representations.
                // When inbound sync sets assetRef on a representation, we need to re-fire loadImage.
                guard let context = item.managedObjectContext else { return }
                let userInfo = notification.userInfo
                let updatedIDs = (userInfo?[NSUpdatedObjectIDsKey] as? Set<NSManagedObjectID>) ?? []
                let insertedIDs = (userInfo?[NSInsertedObjectIDsKey] as? Set<NSManagedObjectID>) ?? []
                let changed = updatedIDs.union(insertedIDs)
                guard !changed.isEmpty else { return }
                context.perform {
                    let repIDs = (item.representations ?? []).map(\.objectID)
                    guard repIDs.contains(where: { changed.contains($0) }) else { return }
                    Task { @MainActor in imageRepVersion += 1 }
                }
            }
            .accessibilityLabel(item.primaryText ?? "Image")
            .accessibilityHint("Pinch to zoom, drag to pan, double tap to toggle zoom")
        }
    }

    #if canImport(UIKit) || canImport(AppKit)
    @ViewBuilder
    private func imageView(_ image: ViewerImage) -> some View {
        let displaySize = baseImageSize(for: image)

        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: displaySize.width, height: displaySize.height)
            .scaleEffect(activeScale)
            .offset(activeOffset)
            .gesture(interactionGesture)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    if scale > 1.1 {
                        scale = 1
                        offset = .zero
                    } else {
                        scale = 2.5
                        offset = clampedOffset(offset, for: scale)
                    }
                }
            }
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: displaySize.width, height: displaySize.height)
            .scaleEffect(activeScale)
            .offset(activeOffset)
            .gesture(interactionGesture)
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    if scale > 1.1 {
                        scale = 1
                        offset = .zero
                    } else {
                        scale = 2.5
                        offset = clampedOffset(offset, for: scale)
                    }
                }
            }
        #endif
    }

    private var interactionGesture: some Gesture {
        SimultaneousGesture(magnificationGesture, panGesture)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                scale = clampedScale(scale * value)
                offset = clampedOffset(offset, for: scale)
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                guard activeScale > 1 else {
                    state = .zero
                    return
                }
                state = value.translation
            }
            .onEnded { value in
                guard activeScale > 1 else {
                    offset = .zero
                    return
                }

                let proposed = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                offset = clampedOffset(proposed, for: scale)
            }
    }

    private var editControlsBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 16) {
                MartenGlassSurface(cornerRadius: 100, padding: 0, isInteractive: true) {
                    editActionButton(
                        systemImage: "rotate.left",
                        accessibilityLabel: "Rotate Left"
                    ) {
                        rotateImage(clockwise: false)
                    }
                }
                .fixedSize()
                .clipShape(Circle())

                MartenGlassSurface(cornerRadius: 100, padding: 0, isInteractive: true) {
                    editActionButton(
                        systemImage: "rotate.right",
                        accessibilityLabel: "Rotate Right"
                    ) {
                        rotateImage(clockwise: true)
                    }
                }
                .fixedSize()
                .clipShape(Circle())

                MartenGlassSurface(cornerRadius: 100, padding: 0, isInteractive: true) {
                    editActionButton(
                        systemImage: "arrow.counterclockwise",
                        accessibilityLabel: "Reset",
                        tint: .red,
                        isEnabled: didEditImage
                    ) {
                        resetImageEdits()
                    }
                }
                .fixedSize()
                .clipShape(Circle())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func editActionButton(
        systemImage: String,
        accessibilityLabel: String,
        tint: Color = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: MartenButtonSize.iconButton, height: MartenButtonSize.iconButton)
                .contentShape(Rectangle())
                .foregroundStyle(isEnabled ? tint : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var imageTaskID: String {
        "\(item.objectID.uriRepresentation().absoluteString)-\(imageRepVersion)"
    }

    private var displayedImage: ViewerImage? {
        if mode == .edit {
            return editedImage ?? image
        }
        return image
    }

    private var activeScale: CGFloat {
        clampedScale(scale * gestureScale)
    }

    private var activeOffset: CGSize {
        let proposed = CGSize(
            width: offset.width + gestureOffset.width,
            height: offset.height + gestureOffset.height
        )
        return clampedOffset(proposed, for: activeScale)
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        max(1, min(value, 8))
    }

    private func updateViewportSize(_ size: CGSize) {
        viewportSize = size
        offset = clampedOffset(offset, for: scale)
    }

    private func clampedOffset(_ candidate: CGSize, for scale: CGFloat) -> CGSize {
        guard scale > 1 else { return .zero }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return .zero }
        guard let displayedImage else { return .zero }

        let base = baseImageSize(for: displayedImage)
        guard base.width > 0, base.height > 0 else { return .zero }

        let scaledWidth = base.width * scale
        let scaledHeight = base.height * scale

        let horizontalLimit = max(0, (scaledWidth - viewportSize.width) / 2)
        let verticalLimit = max(0, (scaledHeight - viewportSize.height) / 2)

        return CGSize(
            width: min(max(candidate.width, -horizontalLimit), horizontalLimit),
            height: min(max(candidate.height, -verticalLimit), verticalLimit)
        )
    }

    private func baseImageSize(for image: ViewerImage) -> CGSize {
        let size = platformImageSize(image)
        guard size.width > 0, size.height > 0 else { return .zero }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return size }

        let fitScale = min(viewportSize.width / size.width, viewportSize.height / size.height)
        let adjusted = max(0, fitScale)

        return CGSize(width: size.width * adjusted, height: size.height * adjusted)
    }

    private func handleDone() {
        if mode == .edit,
           didEditImage,
           let editedImage,
           let editedData = pngData(from: editedImage)
        {
            onSaveEdits?(editedData)
        }

        dismiss()
    }

    private func rotateImage(clockwise: Bool) {
        guard mode == .edit else { return }
        guard let source = editedImage ?? image else { return }
        guard let rotated = rotatedImage(source, clockwise: clockwise) else { return }

        withAnimation(.snappy(duration: 0.2)) {
            editedImage = rotated
            didEditImage = true
            scale = 1
            offset = .zero
        }
    }

    private func resetImageEdits() {
        withAnimation(.snappy(duration: 0.2)) {
            editedImage = image
            didEditImage = false
            scale = 1
            offset = .zero
        }
    }

    private func rotatedImage(_ source: ViewerImage, clockwise: Bool) -> ViewerImage? {
        guard let cgImage = cgImage(from: source) else { return nil }

        let originalSize = CGSize(width: cgImage.width, height: cgImage.height)
        let rotatedSize = CGSize(width: originalSize.height, height: originalSize.width)
        let angle: CGFloat = clockwise ? (.pi / 2) : (-.pi / 2)

        let bitsPerComponent = cgImage.bitsPerComponent > 0 ? cgImage.bitsPerComponent : 8
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: Int(rotatedSize.width),
            height: Int(rotatedSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: angle)
        context.translateBy(x: -originalSize.width / 2, y: -originalSize.height / 2)
        context.draw(cgImage, in: CGRect(origin: .zero, size: originalSize))

        guard let output = context.makeImage() else { return nil }

        #if canImport(UIKit)
        return UIImage(cgImage: output)
        #elseif canImport(AppKit)
        return NSImage(cgImage: output, size: NSSize(width: rotatedSize.width, height: rotatedSize.height))
        #else
        return nil
        #endif
    }

    private func cgImage(from image: ViewerImage) -> CGImage? {
        #if canImport(UIKit)
        if let cgImage = image.cgImage {
            return cgImage
        }
        if let ciImage = image.ciImage {
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }
        return nil
        #elseif canImport(AppKit)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }

    private func pngData(from image: ViewerImage) -> Data? {
        #if canImport(UIKit)
        return image.pngData()
        #elseif canImport(AppKit)
        guard let cgImage = cgImage(from: image) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }

    private func platformImageSize(_ image: ViewerImage) -> CGSize {
        #if canImport(UIKit)
        return image.size
        #elseif canImport(AppKit)
        return CGSize(width: image.size.width, height: image.size.height)
        #else
        return .zero
        #endif
    }
    #endif

    private func loadImage() async {
        let loaded = await ImageThumbnailLoader.shared.loadThumbnail(for: item, maxPixelSize: 2_048)
        image = loaded
        editedImage = loaded
        didEditImage = false
        scale = 1
        offset = .zero
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
