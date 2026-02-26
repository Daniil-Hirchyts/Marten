import MartenCore
import SwiftUI

struct WatchItemDetailView: View {
    @Bindable var container: MartenWatchContainer
    let item: WatchClipSummary

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirmation = false
    @State private var isPerformingAction = false
    @State private var isShowingMoveSheet = false
    @State private var draftText: String

    init(container: MartenWatchContainer, item: WatchClipSummary) {
        self.container = container
        self.item = item
        _draftText = State(initialValue: item.preferredText)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                contentCard
                editAndMoveCard
                metadataCard
                actionsCard
            }
            .padding(.horizontal, WatchVisualSystem.outerPadding)
            .padding(.bottom, 64)
        }
        .navigationTitle("Card")
        .sheet(isPresented: $isShowingMoveSheet) {
            moveToPinboardSheet
        }
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
        .alert("Delete Card?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteItem()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                WatchMetadataPill(title: itemTypeLabel, systemImage: currentItem.systemImageName)
                WatchMetadataPill(
                    title: WatchRelativeTime.short(from: currentItem.modifiedAt),
                    systemImage: "clock",
                    tint: .secondary
                )

                if currentItem.isPinned {
                    WatchMetadataPill(title: "Pinned", systemImage: "pin.fill", tint: .orange)
                }
            }

            Text(currentItem.preferredText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let sourceAppName {
                Label(sourceAppName, systemImage: "app.badge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .watchCard(prominence: .normal)
    }

    private var editAndMoveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchSectionTitle(title: "Edit", detail: nil)

            if supportsTextEditing {
                ZStack {
                    Button(action: {}) {
                        Label("Edit Text", systemImage: "pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .allowsHitTesting(false)
                    
                    TextField("Edit text", text: $draftText)
                        .labelsHidden()
                        .opacity(0.011)
                        .onSubmit {
                            saveEditedText()
                        }
                }
                .disabled(isPerformingAction)
            }

            Button {
                isShowingMoveSheet = true
            } label: {
                Label("Move to Pinboard", systemImage: "tray")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingAction || container.customPinboards.isEmpty)

            if currentPinboardNames.isEmpty {
                Text("Only in All cards")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(currentPinboardNames.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .watchCard(prominence: .subtle)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchSectionTitle(title: "Metadata", detail: nil)

            LabeledContent("Updated", value: WatchRelativeTime.short(from: currentItem.modifiedAt))
            LabeledContent("Created", value: currentItem.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent(
                "Size",
                value: ByteCountFormatter.string(fromByteCount: currentItem.byteCount, countStyle: .file)
            )
        }
        .font(.caption)
        .watchCard(prominence: .subtle)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchSectionTitle(title: "Actions", detail: nil)

            HStack(spacing: 8) {
                Button {
                    markUsed()
                } label: {
                    Label("Use", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)

                Button {
                    togglePin()
                } label: {
                    Label(currentItem.isPinned ? "Unpin" : "Pin", systemImage: currentItem.isPinned ? "pin.slash" : "pin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
            }

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isPerformingAction)
        }
        .watchCard(prominence: .subtle)
    }

    private var quickEditButton: some View {
        WatchFloatingTextFieldBindingActionButton(
            systemImage: "pencil",
            accessibilityLabel: "Edit card text",
            title: "Edit text",
            text: $draftText
        ) {
            saveEditedText()
        }
    }

    private var moveToPinboardSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                    WatchSectionTitle(title: "Pinboards", detail: "\(container.customPinboards.count)")

                    if container.customPinboards.isEmpty {
                        Text("No pinboards available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .watchCard(prominence: .subtle)
                    } else {
                        ForEach(container.customPinboards) { pinboard in
                            Button {
                                moveItemFromSheet(to: pinboard.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Label(
                                        pinboard.name,
                                        systemImage: currentItem.pinboardIDs.contains(pinboard.id)
                                            ? "checkmark.circle.fill" : "circle"
                                    )
                                    .lineLimit(1)

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .watchCard(prominence: currentItem.pinboardIDs.contains(pinboard.id) ? .accent : .normal)
                            .disabled(isPerformingAction)
                        }
                    }
                }
                .padding(.horizontal, WatchVisualSystem.outerPadding)
                .padding(.bottom, WatchVisualSystem.outerPadding)
            }
            .navigationTitle("Pinboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingMoveSheet = false
                    }
                    .disabled(isPerformingAction)
                }
            }
        }
    }

    private var currentItem: WatchClipSummary {
        container.items.first(where: { $0.id == item.id }) ?? item
    }

    private var sourceAppName: String? {
        guard let source = currentItem.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty
        else {
            return nil
        }

        return source
    }

    private var supportsTextEditing: Bool {
        switch currentItem.itemType {
        case .text:
            return true
        default:
            return false
        }
    }

    private var currentPinboardNames: [String] {
        let names = container.customPinboards
            .filter { currentItem.pinboardIDs.contains($0.id) }
            .map(\.name)
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var itemTypeLabel: String {
        switch currentItem.itemType {
        case .text: return "Text"
        case .richText: return "Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "URL"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }

    private func markUsed() {
        guard !isPerformingAction else { return }
        isPerformingAction = true

        Task { @MainActor in
            _ = await container.markItemUsed(itemID: currentItem.id)
            isPerformingAction = false
        }
    }

    private func togglePin() {
        guard !isPerformingAction else { return }
        isPerformingAction = true

        Task { @MainActor in
            _ = await container.togglePin(itemID: currentItem.id)
            isPerformingAction = false
        }
    }

    private func moveItemFromSheet(to pinboardID: UUID) {
        let isCurrent = currentItem.pinboardIDs.contains(pinboardID)
        guard !isPerformingAction else { return }
        isPerformingAction = true

        Task { @MainActor in
            let moved = await container.setItemPinboardMembership(
                itemID: currentItem.id,
                pinboardID: pinboardID,
                isMember: !isCurrent
            )
            isPerformingAction = false
            if moved {
                isShowingMoveSheet = false
            }
        }
    }

    private func saveEditedText() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentItem.preferredText, !isPerformingAction else { return }
        isPerformingAction = true

        Task { @MainActor in
            _ = await container.updateTextItem(itemID: currentItem.id, newText: trimmed)
            isPerformingAction = false
        }
    }

    private func deleteItem() {
        guard !isPerformingAction else { return }
        isPerformingAction = true

        Task { @MainActor in
            let deleted = await container.deleteItem(itemID: currentItem.id)
            isPerformingAction = false
            if deleted {
                dismiss()
            }
        }
    }
}
