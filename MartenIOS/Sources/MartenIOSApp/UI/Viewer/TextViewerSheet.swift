import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TextViewerSheet: View {
    let item: ClipItem
    var onEdit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var sourceText: String {
        item.plainTextContent ?? item.primaryText ?? ""
    }

    private var sheetTitle: String {
        "Text"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(sourceText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .navigationTitle(sheetTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyToPasteboard()
                        withAnimation(MartenAnimation.quick) {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(MartenAnimation.quick) {
                                copied = false
                            }
                        }
                    } label: {
                        Label(
                            copied ? "Copied" : "Copy",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                    }

                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
            }
            .accessibilityLabel("\(sheetTitle) preview")
        }
    }

    private func copyToPasteboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = sourceText
        #endif
    }
}
