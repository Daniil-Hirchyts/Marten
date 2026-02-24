import SwiftUI

struct WatchPinboardCardsView: View {
    @Bindable var container: MartenWatchContainer
    let pinboardID: UUID?
    let title: String

    @State private var previewItem: WatchClipSummary?
    @State private var movingItem: WatchClipSummary?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
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
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .watchCard(prominence: .subtle)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(container.items) { item in
                    Button {
                        copyItem(item)
                    } label: {
                        WatchItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            movingItem = item
                        } label: {
                            Image(systemName: "circle.dashed")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
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
            }
        }
        .navigationTitle(title)
        .searchable(
            text: Binding(
                get: { container.searchQuery },
                set: { container.searchQuery = $0 }
            ),
            prompt: "Search cards"
        )
        .refreshable {
            await container.refresh()
        }
        .task(id: pinboardID) {
            container.searchQuery = ""
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
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDisappear {
            toastTask?.cancel()
            toastTask = nil
        }
    }

    private var emptyMessage: String {
        let trimmed = container.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "No cards in this pinboard yet."
        }

        return "No matching cards."
    }

    private func copyItem(_ item: WatchClipSummary) {
        Task { @MainActor in
            _ = WatchClipboardBridge.copy(text: item.preferredText)
            _ = await container.markItemUsed(itemID: item.id)
            WatchClipboardBridge.playSuccessHaptic()
            showToast("Copied")
        }
    }

    private func deleteItem(_ item: WatchClipSummary) {
        Task { @MainActor in
            _ = await container.deleteItem(itemID: item.id)
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = message
        }

        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }
}
