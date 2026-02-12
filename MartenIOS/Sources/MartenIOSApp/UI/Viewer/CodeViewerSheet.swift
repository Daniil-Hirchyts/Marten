import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CodeViewerSheet: View {
    let item: ClipItem

    @Environment(\.dismiss) private var dismiss
    @State private var highlightedSource: AttributedString = AttributedString("")
    @State private var copied = false

    private var sourceText: String {
        item.plainTextContent ?? item.primaryText ?? ""
    }

    private var lineCount: Int {
        sourceText.components(separatedBy: "\n").count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers gutter
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(1...max(1, lineCount), id: \.self) { line in
                            Text("\(line)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(height: 20)
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.top, 14)

                    Divider()
                        .padding(.vertical, 8)

                    Text(highlightedSource)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .accessibilityLabel("Code content")
                }
            }
            .navigationTitle("Code")
            .viewerSheetTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copySourceToPasteboard()
                        withAnimation(MartenAnimation.quick) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(MartenAnimation.quick) { copied = false }
                        }
                    } label: {
                        Label(
                            copied ? "Copied" : "Copy",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
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
