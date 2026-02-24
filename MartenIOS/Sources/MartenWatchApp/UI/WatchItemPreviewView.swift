import SwiftUI

struct WatchItemPreviewView: View {
    @Bindable var container: MartenWatchContainer
    let item: WatchClipSummary

    @State private var isShowingEditSheet = false
    @State private var draftText = ""
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                previewContent
            }
            .padding(.horizontal, WatchVisualSystem.outerPadding)
            .padding(.bottom, 64)
        }
        .navigationTitle("Preview")
        .overlay(alignment: .bottomTrailing) {
            if supportsTextEditing {
                quickEditButton
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            editSheet
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch currentItem.itemType {
        case .image:
            VStack(alignment: .center, spacing: 10) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("Image")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        default:
            Text(currentItem.preferredText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickEditButton: some View {
        WatchFloatingGlassActionButton(
            systemImage: "pencil",
            accessibilityLabel: "Edit card text"
        ) {
            draftText = currentItem.preferredText
            isShowingEditSheet = true
        }
    }

    private var editSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                    TextField("Edit text", text: $draftText, axis: .vertical)
                        .lineLimit(4...12)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, WatchVisualSystem.outerPadding)
                .padding(.bottom, 58)
            }
            .navigationTitle("Edit")
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingEditSheet = false
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            saveText()
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(isSaving ? "Saving" : "Save")
                    .frame(maxWidth: .infinity)
            }
        }
        .watchProminentGlassButtonStyle()
        .buttonBorderShape(.capsule)
        .disabled(isSaving || draftCharacterCount == 0)
        .padding(.horizontal, WatchVisualSystem.outerPadding)
        .padding(.top, 4)
    }

    private var supportsTextEditing: Bool {
        switch currentItem.itemType {
        case .text:
            return true
        default:
            return false
        }
    }

    private var currentItem: WatchClipSummary {
        container.items.first(where: { $0.id == item.id }) ?? item
    }

    private var draftCharacterCount: Int {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private func saveText() {
        guard !isSaving else { return }
        isSaving = true

        Task { @MainActor in
            let updated = await container.updateTextItem(itemID: currentItem.id, newText: draftText)
            isSaving = false
            if updated {
                isShowingEditSheet = false
            }
        }
    }
}
