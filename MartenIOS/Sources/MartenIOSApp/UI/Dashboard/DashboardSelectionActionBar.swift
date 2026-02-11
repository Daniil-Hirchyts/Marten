import SwiftUI

struct DashboardSelectionActionBar: View {
    let selectedCount: Int
    let onCopy: () -> Void
    let onMove: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        MartenGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                actionButton(title: "Copy", systemImage: "doc.on.doc", action: onCopy)
                actionButton(title: "Move", systemImage: "tray.full", action: onMove)
                actionButton(title: "Share", systemImage: "square.and.arrow.up", action: onShare)
                actionButton(
                    title: "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )

                Spacer(minLength: 12)

                Button("Done") {
                    onCancel()
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.clear)
        }
        .overlay(alignment: .topLeading) {
            Text("\(selectedCount) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: .capsule)
                .offset(x: 14, y: -14)
                .accessibilityLabel("\(selectedCount) items selected")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : nil)
    }
}
