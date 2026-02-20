import AppKit
import SwiftUI

struct ImagePreview: View {
    let image: NSImage?
    var onRotate: ((RotationDirection) -> Void)? = nil
    var onSaveAs: (() -> Void)? = nil
    
    enum RotationDirection {
        case left, right
    }
    
    @State private var isHovering = false

    var body: some View {
        Group {
            if let image {
                ZStack(alignment: .topTrailing) {
                    // Image with transparency grid
                    ZStack {
                        TransparencyGrid(squareSize: 8)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    }

                    // Floating action buttons (visible on hover - not rotated)
                    if isHovering, onRotate != nil || onSaveAs != nil {
                        HStack(spacing: 8) {
                            if let onRotate {
                                Button(action: { onRotate(.left) }) {
                                    Image(systemName: "rotate.left")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.6))
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                                .help("Rotate Left")
                                
                                Button(action: { onRotate(.right) }) {
                                    Image(systemName: "rotate.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.6))
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                                .help("Rotate Right")
                            }
                            
                            if let onSaveAs {
                                Button(action: onSaveAs) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.6))
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                                .help("Save As...")
                            }
                        }
                        .padding(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .onHover { hovering in
                    withAnimation(OverlayAnimation.standardTransition) {
                        isHovering = hovering
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }
}
