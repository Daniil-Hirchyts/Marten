import SwiftUI

struct QuickAddMenuSheet: View {
    @Bindable var container: MartenIOSAppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    activeSheet = .newText
                } label: {
                    Label("New Text", systemImage: "square.and.pencil")
                }
                .accessibilityHint("Create a new text clip")

                Button {
                    Task {
                        await container.createItemFromClipboard()
                        dismiss()
                    }
                } label: {
                    Label("Paste Clipboard", systemImage: "doc.on.clipboard")
                }
                .accessibilityHint("Save current clipboard contents")

                Button {
                    activeSheet = .scan
                } label: {
                    Label("Scan Document", systemImage: "doc.text.viewfinder")
                }
                .accessibilityHint("Scan a document with the camera")
            }
            .navigationTitle("Quick Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newText:
                NewTextItemSheet { text in
                    Task {
                        await container.createTextItem(text)
                    }
                }
            case .scan:
                DocumentScannerSheet { pages in
                    Task {
                        await container.createScannedPages(pages)
                    }
                }
            }
        }
    }
}

private enum ActiveSheet: String, Identifiable {
    case newText
    case scan

    var id: String { rawValue }
}
