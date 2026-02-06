import AppKit
import SwiftUI

@MainActor
struct ImageEditorView: View {
    let byteCount: Int64
    let image: NSImage?
    let rotationAngle: Angle
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void
    let onCopy: () -> Void
    let onSaveAs: () -> Void

    @Binding var fileName: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                if let image {
                    ZStack {
                        TransparencyGrid(squareSize: 10)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(rotationAngle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 8) {
                        actionButton(icon: "rotate.left", tooltip: "Rotate Left", action: onRotateLeft)
                        actionButton(icon: "rotate.right", tooltip: "Rotate Right", action: onRotateRight)
                        actionButton(icon: "doc.on.doc", tooltip: "Copy", action: onCopy)
                        actionButton(icon: "square.and.arrow.down", tooltip: "Save As...", action: onSaveAs)
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.50))
                        Text("Loading image...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.50))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            VStack(spacing: 12) {
                if let image {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "aspectratio")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.50))
                            Text("\(Int(image.size.width))×\(Int(image.size.height))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.70))
                        }

                        if byteCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.50))
                                Text(ItemEditorHelpers.formatFileSize(byteCount))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.primary.opacity(0.70))
                            }
                        }

                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    Text("Rename:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.60))

                    TextField("", text: $fileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func actionButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
        .help(tooltip)
    }
}

