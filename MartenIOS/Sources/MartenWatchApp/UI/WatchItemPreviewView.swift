import SwiftUI

struct WatchItemPreviewView: View {
    @Bindable var container: MartenWatchContainer
    let item: WatchClipSummary

    @State private var draftText: String

    init(container: MartenWatchContainer, item: WatchClipSummary) {
        self.container = container
        self.item = item
        _draftText = State(initialValue: item.preferredText)
    }

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
        .onChange(of: currentItem.preferredText) { old, new in
            if draftText != new {
                draftText = new
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch currentItem.itemType {
        case .image:
            if let path = currentItem.thumbnailPath {
                WatchThumbnailImage(path: path)
                    .clipShape(RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Image")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        case .file:
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: currentItem.systemImageName)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text(currentItem.preferredText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(WatchVisualSystem.cardPadding)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        case .color:
            if let hex = currentItem.colorHex {
                VStack(alignment: .center, spacing: 16) {
                    RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                        .fill(Color.watchColor(hex: hex, fallback: .gray))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 3)

                    Text(hex)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            } else {
                Text(currentItem.preferredText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .url:
            Text(currentItem.preferredText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(currentItem.preferredText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickEditButton: some View {
        WatchFloatingTextFieldBindingActionButton(
            systemImage: "pencil",
            accessibilityLabel: "Edit card text",
            title: "Edit text",
            text: $draftText
        ) {
            saveText()
        }
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

    private func saveText() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentItem.preferredText else { return }

        Task { @MainActor in
            _ = await container.updateTextItem(itemID: currentItem.id, newText: trimmed)
        }
    }
}
