import MartenCore
import SwiftUI

struct LinkEditorSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var linkText: String

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _linkText = State(initialValue: item.primaryText ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    TextField("https://example.com", text: $linkText)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif

                    if let normalizedURL {
                        Button {
                            openURL(normalizedURL)
                        } label: {
                            Label("Open Link", systemImage: "safari")
                        }
                    } else {
                        Text("Enter a valid URL")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        guard let normalized = normalizedURLString else { return }
                        onSave(normalized)
                        dismiss()
                    }
                    .disabled(normalizedURL == nil)
                }
            }
        }
    }

    private var normalizedURLString: String? {
        Self.normalizedURLString(from: linkText)
    }

    private var normalizedURL: URL? {
        guard let normalizedURLString else { return nil }
        return URL(string: normalizedURLString)
    }

    private static func normalizedURLString(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            return parsed.absoluteString
        }

        let prefixed = "https://\(trimmed)"
        guard let parsed = URL(string: prefixed), parsed.host != nil else { return nil }
        return parsed.absoluteString
    }
}
