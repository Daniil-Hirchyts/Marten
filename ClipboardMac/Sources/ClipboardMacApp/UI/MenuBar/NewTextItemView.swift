import SwiftUI

struct NewTextItemView: View {
    @State private var text = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Text Item")
                .font(.system(size: 14, weight: .semibold))

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                Spacer()
                Button("Create") {
                    onSave(text)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

struct NewTextItemSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NewTextItemView(onSave: onSave, onCancel: onCancel)
    }
}
