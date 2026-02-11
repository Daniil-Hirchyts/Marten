import SwiftUI

struct NewTextItemSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Text content")
                }
            }
            .navigationTitle("New Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Save the text as a new clip")
                }
            }
        }
    }
}
