import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CodeViewerSheet: View {
    let item: ClipItem

    @Environment(\.dismiss) private var dismiss
    @State private var highlightedSource: AttributedString = AttributedString("")

    private var sourceText: String {
        item.plainTextContent ?? item.primaryText ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(highlightedSource)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .accessibilityLabel("Code content")
            }
            .navigationTitle("Code")
            .viewerSheetTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copySourceToPasteboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .accessibilityHint("Copy code to clipboard")
                }
            }
            .task(id: item.objectID) {
                highlightedSource = CodeSyntaxHighlighter.highlighted(sourceText)
            }
        }
    }

    private func copySourceToPasteboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = sourceText
        #endif
    }
}

#if !os(iOS)
private extension View {
    func viewerSheetTitleDisplayMode() -> some View { self }
}
#else
private extension View {
    func viewerSheetTitleDisplayMode() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }
}
#endif
