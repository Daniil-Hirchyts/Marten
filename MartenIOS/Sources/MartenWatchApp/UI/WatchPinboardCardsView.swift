import SwiftUI

struct WatchPinboardCardsView: View {
    @Bindable var container: MartenWatchContainer
    let pinboardID: UUID?
    let title: String

    @State private var previewItem: WatchClipSummary?
    @State private var movingItem: WatchClipSummary?
    @State private var copiedItemID: UUID?
    @State private var copiedOverlayTask: Task<Void, Never>?

    private var pinboardLookup: [UUID: WatchPinboardSummary] {
        Dictionary(uniqueKeysWithValues: container.customPinboards.map { ($0.id, $0) })
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if container.isSelectedPinboardAwaitingUnlock {
                    WatchLockedPinboardView(
                        title: container.selectedPinboardTitle,
                        isAuthenticating: container.lockStateStore.isAuthenticating,
                        onUnlock: {
                            Task {
                                _ = await container.unlockSelectedPinboard()
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                } else if container.isLoadingItems {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        ProgressView()
                        Text("Loading")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .watchCard(prominence: .subtle)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                } else if container.items.isEmpty {
                    WatchEmptyPinboardView()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(container.items) { item in
                                            let row = WatchItemRow(
                                                item: item,
                                                viewingPinboardID: pinboardID,
                                                pinboardLookup: pinboardLookup,
                                                isCopied: copiedItemID == item.id
                                            )
                                            
                                            Button {
                                                copyItem(item, proxy: proxy)
                                            } label: {
                                                row
                                            }
                                            .id(item.id)
                                            .buttonStyle(WatchCardButtonStyle(prominence: row.cardProminence))
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                movingItem = item
                            } label: {
                                Image(systemName: "circle.dashed")
                            }
                            .tint(.blue)

                            Button {
                                previewItem = item
                            } label: {
                                Image(systemName: "eye")
                            }
                            .tint(.blue)
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowBackground(Color.clear)
                    }

                    Color.clear.frame(height: 56)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(title)
        .refreshable {
            await container.refresh()
        }
        .overlay(alignment: .bottomTrailing) {
            if !container.isSelectedPinboardAwaitingUnlock {
                WatchFloatingTextFieldLinkActionButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add item to pinboard",
                    prompt: "Type or dictate"
                ) { text in
                    Task { @MainActor in
                        _ = await container.createTextItemInPinboard(text, pinboardID: pinboardID)
                    }
                }
            }
        }
        .task(id: pinboardID) {
            container.selectPinboard(pinboardID)
            await container.refresh()
        }
        .sheet(item: $previewItem) { item in
            NavigationStack {
                WatchItemPreviewView(container: container, item: item)
            }
        }
        .sheet(item: $movingItem) { item in
            NavigationStack {
                WatchMoveToPinboardSheet(container: container, item: item)
            }
        }
        .onDisappear {
            copiedOverlayTask?.cancel()
            copiedOverlayTask = nil
        }
    }


    private func copyItem(_ item: WatchClipSummary, proxy: ScrollViewProxy) {
        Task { @MainActor in
            _ = WatchClipboardBridge.copy(text: item.preferredText)
            WatchClipboardBridge.playSuccessHaptic()
            
            copiedOverlayTask?.cancel()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                copiedItemID = item.id
            }
            
            copiedOverlayTask = Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        copiedItemID = nil
                    }
                }
            }
        }
    }

    private func deleteItem(_ item: WatchClipSummary) {
        Task { @MainActor in
            _ = await container.deleteItem(itemID: item.id)
        }
    }
}

private struct WatchEmptyPinboardView: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Nothing Here Yet")
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
    }
}
