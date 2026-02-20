import AppKit
import SwiftUI

struct RenameOverlayView: View {
    @Binding var title: String
    var onSave: () -> Void
    var onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Item")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit {
                    onSave()
                }
                .accessibilityIdentifier("overlay.rename.title")
                .accessibilityLabel("Title")
                .accessibilityValue(title.isEmpty ? "Empty" : title)
                .accessibilityHint("Enter a new title")

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overlay.rename.cancel")
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismisses without saving")

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("overlay.rename.save")
                .accessibilityLabel("Save")
                .accessibilityHint("Saves the new title")
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}
