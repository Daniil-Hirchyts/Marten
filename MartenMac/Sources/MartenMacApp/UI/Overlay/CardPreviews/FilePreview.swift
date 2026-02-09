import AppKit
import SwiftUI

struct FilePreview: View {
    let icon: NSImage?
    let name: String
    let size: String?
    var onSaveAs: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background card
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.05)
                )
            
            // Icon and label
            VStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(
                            colorScheme == .dark
                                ? Color.white.opacity(0.6)
                                : Color.black.opacity(0.3)
                        )
                }
                
                if let size {
                    Text(size)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Floating save button (visible on hover)
            if isHovering, let onSaveAs {
                Button(action: onSaveAs) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                )
                .help("Save As...")
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
