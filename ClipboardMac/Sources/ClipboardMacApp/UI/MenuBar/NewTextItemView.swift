import SwiftUI

struct NewTextItemView: View {
    @State private var text = ""
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Text Item")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityIdentifier("menubar.newTextItem.title")
                .accessibilityLabel("New Text Item Title")

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .accessibilityIdentifier("menubar.newTextItem.textEditor")
                .accessibilityLabel("New Text Item Text")

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .accessibilityIdentifier("menubar.newTextItem.cancel")
                .accessibilityLabel("Cancel New Text Item")
                Spacer()
                Button("Create") {
                    onSave(text)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("menubar.newTextItem.create")
                .accessibilityLabel("Create New Text Item")
            }
        }
        .padding(16)
        .frame(width: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menubar.newTextItem.view")
        .accessibilityLabel("New Text Item View")
    }
}

struct NewTextItemSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NewTextItemView(onSave: onSave, onCancel: onCancel)
    }
}
