import SwiftUI

struct QuickAddMenuSheet: View {
    @Bindable var container: MartenIOSAppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    quickAddButton(
                        title: "New Text",
                        systemImage: "square.and.pencil",
                        color: .blue
                    ) {
                        activeSheet = .newText
                    }

                    quickAddButton(
                        title: "Paste",
                        systemImage: "doc.on.clipboard",
                        color: .green
                    ) {
                        Task {
                            await container.createItemFromClipboard()
                            dismiss()
                        }
                    }

                    quickAddButton(
                        title: "Scan",
                        systemImage: "doc.text.viewfinder",
                        color: .orange
                    ) {
                        activeSheet = .scan
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()
            }
            .navigationTitle("Quick Add")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newText:
                NewTextItemSheet(
                    appleIntelligence: container.appleIntelligence
                ) { plainText, rtfData in
                    Task {
                        await container.createRichTextItem(plainText: plainText, rtfData: rtfData)
                    }
                }
            case .scan:
                DocumentScannerSheet { pages in
                    Task { await container.createScannedPages(pages) }
                }
            }
        }
    }

    private func quickAddButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(
                        width: MartenButtonSize.largeIconButton,
                        height: MartenButtonSize.largeIconButton
                    )
                    .background(color.opacity(0.12), in: .circle)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Create a new \(title.lowercased()) clip")
    }
}

private enum ActiveSheet: String, Identifiable {
    case newText
    case scan

    var id: String { rawValue }
}
