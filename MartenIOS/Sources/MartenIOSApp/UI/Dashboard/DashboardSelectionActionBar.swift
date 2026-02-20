import SwiftUI

struct DashboardSelectionActionBar: View {
    let selectedCount: Int
    let onCopy: () -> Void
    let onMove: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var pressedButton: String?
    @State private var hoveredButton: String?
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            // Group: Move | Copy | Share
            MartenGlassSurface(cornerRadius: 100, padding: 0, isInteractive: true) {
                HStack(spacing: 0) {
                    // Move
                    actionButtonInGroup(
                        id: "move",
                        systemImage: "circle.dashed",
                        label: "Move to Pinboard",
                        action: onMove
                    )

                    Divider()
                        .frame(height: 24)

                    // Copy
                    actionButtonInGroup(
                        id: "copy",
                        systemImage: "doc.on.doc",
                        label: "Copy to Clipboard",
                        action: onCopy
                    )

                    Divider()
                        .frame(height: 24)

                    // Share
                    actionButtonInGroup(
                        id: "share",
                        systemImage: "square.and.arrow.up",
                        label: "Share",
                        action: onShare
                    )
                }
                .clipShape(Capsule())
            }
            .fixedSize()
            
            // Small spacing between Group and Delete
            Spacer().frame(width: 12)
            
            // Delete (Right)
            actionButton("Delete", systemImage: "trash", tint: .red, action: onDelete)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.opacity)
    }
    
    private func actionButtonInGroup(
        id: String,
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            pressedButton = id
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pressedButton = nil
            }
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: MartenButtonSize.iconButton, height: MartenButtonSize.iconButton)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
                .opacity(pressedButton == id ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .background(
            Rectangle()
                .fill(hoveredButton == id ? Color.primary.opacity(0.12) : Color.clear)
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                if isHovered {
                    hoveredButton = id
                } else if hoveredButton == id {
                    hoveredButton = nil
                }
            }
        }
        .accessibilityLabel(label)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: MartenButtonSize.iconButton, height: MartenButtonSize.iconButton)
                .contentShape(Rectangle())
                .foregroundStyle(tint ?? .primary)
        }
        .buttonStyle(.plain)
        .glassCircleBackground(isHighlighted: false)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: title) { _, _ in true }
        .accessibilityLabel(title)
    }
}
