import AppKit
import SwiftUI

@MainActor
struct ImageEditorView: View {
    let image: NSImage?
    let rotationAngle: Angle

    var body: some View {
        ZStack {
            if let image {
                TransparencyGrid(squareSize: 10)

                ZoomableNSImageView(image: image, rotationAngle: rotationAngle)
                    .padding(12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Loading image…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct ZoomableNSImageView: NSViewRepresentable {
    let image: NSImage
    let rotationAngle: Angle

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 6.0
        scrollView.drawsBackground = false
        
        let clipView = CenteredClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        scrollView.documentView = imageView

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let imageView = scrollView.documentView as? NSImageView {
            let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
            let rotatedImage = ItemEditorHelpers.applyRotation(to: image, degrees: totalRotation)
            
            imageView.image = rotatedImage
            imageView.frame = NSRect(origin: .zero, size: rotatedImage.size)
            
            if !context.coordinator.didInitialFit {
                DispatchQueue.main.async {
                    context.coordinator.fitToScrollView(scrollView, imageSize: rotatedImage.size)
                }
                context.coordinator.didInitialFit = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var didInitialFit = false
        
        func fitToScrollView(_ scrollView: NSScrollView, imageSize: CGSize) {
            let canvasSize = scrollView.contentSize
            let scaleX = canvasSize.width / imageSize.width
            let scaleY = canvasSize.height / imageSize.height
            let scale = min(scaleX, scaleY)
            
            scrollView.magnification = scale < 1.0 ? scale : 1.0
        }

        @objc func handleDoubleClick(_ gesture: NSGestureRecognizer) {
            guard let scrollView = gesture.view as? NSScrollView,
                  let imageView = scrollView.documentView as? NSImageView,
                  let image = imageView.image else { return }
                  
            let canvasSize = scrollView.contentSize
            let scaleX = canvasSize.width / image.size.width
            let scaleY = canvasSize.height / image.size.height
            let fitScale = min(scaleX, scaleY)
            let idealFitScale = fitScale < 1.0 ? fitScale : 1.0
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                if abs(scrollView.magnification - 1.0) < 0.05 {
                    scrollView.animator().magnification = idealFitScale
                } else {
                    scrollView.animator().magnification = 1.0
                }
            }
        }
    }
}

class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let docView = documentView {
            if docView.frame.width < rect.size.width {
                rect.origin.x = round((docView.frame.width - rect.size.width) / 2.0)
            }
            if docView.frame.height < rect.size.height {
                rect.origin.y = round((docView.frame.height - rect.size.height) / 2.0)
            }
        }
        return rect
    }
}
