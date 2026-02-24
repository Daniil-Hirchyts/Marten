import MartenCore
import SwiftUI

struct CodeEditorSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceText: String

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _sourceText = State(initialValue: item.plainTextContent ?? item.primaryText ?? "")
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $sourceText)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationTitle("Edit Code")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Save") {
                            onSave(sourceText)
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
                }
        }
    }

    private var canSave: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
