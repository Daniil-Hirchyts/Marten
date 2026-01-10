import AppKit
import ClipboardCore
import ClipboardMacServices
import OSLog
import SwiftUI

struct OverlayRootView: View {
    @State private var searchText = ""
    @State private var renamePinboardID: NSManagedObjectID?
    @State private var renamePinboardName = ""
    @State private var isRenamingPinboard = false
    @State private var isCreatingPinboard = false
    @State private var newPinboardName = ""
    @State private var pendingPinboardItem: ClipItem?
    @State private var searchResults: [ClipItem] = []
    @FocusState private var searchFocused: Bool

    private let store = ClipItemStore()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
        predicate: NSPredicate(format: "isTransient == NO"),
        animation: .easeInOut
    )
    private var items: FetchedResults<ClipItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)],
        animation: .easeInOut
    )
    private var pinboards: FetchedResults<Pinboard>

    @State private var selectedPinboardID: UUID?

    private var filteredItems: [ClipItem] {
        if isSearchActive {
            return searchResults
        }

        let query = searchText.normalizedForSearch()
        let base = items.filter { item in
            guard let selectedPinboardID else { return true }
            return item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false
        }

        guard !query.isEmpty else { return Array(base) }
        return base.filter {
            ($0.searchableText ?? "").contains(query) || ($0.primaryText ?? "").normalizedForSearch().contains(query)
        }
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clipboard")
                        .font(.system(size: 14, weight: .semibold))

                    TextField("Search", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($searchFocused)
                }

                PinboardTabBar(
                    pinboards: Array(pinboards),
                    selectedID: selectedPinboardID,
                    onSelect: { selectedPinboardID = $0 },
                    onCreate: { beginPinboardCreate(for: nil) },
                    onRename: { pinboard in
                        renamePinboardID = pinboard.objectID
                        renamePinboardName = pinboard.name
                        isRenamingPinboard = true
                    },
                    onDelete: deletePinboard
                )

                if isSearchActive {
                    SearchModeView(query: searchText, resultCount: filteredItems.count) {
                        searchText = ""
                    }
                    .transition(.opacity)
                }

                Group {
                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        ItemCardRow(
                            items: filteredItems,
                            pinboards: Array(pinboards),
                            onCopy: copyItem,
                            onDelete: deleteItem,
                            onTogglePin: togglePin,
                            onMoveToPinboard: moveItem,
                            onCreatePinboard: { beginPinboardCreate(for: $0) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .alert("Rename Pinboard", isPresented: $isRenamingPinboard) {
            TextField("Name", text: $renamePinboardName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                commitPinboardRename()
            }
        }
        .sheet(isPresented: $isCreatingPinboard) {
            PinboardCreateView(name: $newPinboardName) {
                commitPinboardCreate()
                isCreatingPinboard = false
            } onCancel: {
                isCreatingPinboard = false
            }
        }
        .onChange(of: searchText) { _ in
            updateSearchResults()
        }
        .onChange(of: selectedPinboardID) { _ in
            updateSearchResults()
        }
        .onAppear {
            searchFocused = true
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emptyStateTitle)
                .font(.system(size: 13, weight: .semibold))
            Text(emptyStateText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    private var emptyStateTitle: String {
        if isSearchActive {
            return "No matches"
        }
        if selectedPinboardID != nil {
            return "Pinboard is empty"
        }
        return "Clipboard is empty"
    }

    private var emptyStateText: String {
        if isSearchActive {
            return "No results for \"\(searchText)\". Try another keyword."
        }
        if selectedPinboardID != nil {
            return "No items in this pinboard"
        }
        return "Copy something to get started."
    }

    private func copyItem(_ item: ClipItem) {
        guard let text = item.primaryText, !text.isEmpty else { return }
        NotificationCenter.default.post(name: .clipboardWillWrite, object: nil)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func deleteItem(_ item: ClipItem) {
        do {
            try store.deleteItem(objectID: item.objectID)
        } catch {
            Logger.app.error("Failed to delete item: \(error.localizedDescription)")
        }
    }

    private func togglePin(_ item: ClipItem) {
        let context = item.managedObjectContext
        context?.perform {
            item.isPinned.toggle()
            do {
                try context?.save()
            } catch {
                Logger.app.error("Failed to toggle pin: \(error.localizedDescription)")
            }
        }
    }

    private func deletePinboard(_ pinboard: Pinboard) {
        guard !pinboard.isSystemClipboard else { return }
        if selectedPinboardID == pinboard.id {
            selectedPinboardID = nil
        }
        do {
            try store.deletePinboard(objectID: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to delete pinboard: \(error.localizedDescription)")
        }
    }

    private func commitPinboardRename() {
        guard let objectID = renamePinboardID else { return }
        let trimmedName = renamePinboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            try store.renamePinboard(objectID: objectID, name: trimmedName)
        } catch {
            Logger.app.error("Failed to rename pinboard: \(error.localizedDescription)")
        }
    }

    private func commitPinboardCreate() {
        let trimmedName = newPinboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            let pinboard = try store.createPinboard(name: trimmedName, colorHex: "#808080")
            selectedPinboardID = pinboard.id
            if let pendingPinboardItem {
                try? store.moveItem(objectID: pendingPinboardItem.objectID, toPinboard: pinboard.objectID)
            }
            pendingPinboardItem = nil
        } catch {
            Logger.app.error("Failed to create pinboard: \(error.localizedDescription)")
        }
    }

    private func updateSearchResults() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try store.searchItems(query: trimmed, limit: 100, pinboardID: selectedPinboardID)
        } catch {
            Logger.app.error("Search failed: \(error.localizedDescription)")
            searchResults = []
        }
    }

    private func beginPinboardCreate(for item: ClipItem?) {
        pendingPinboardItem = item
        newPinboardName = ""
        isCreatingPinboard = true
    }

    private func moveItem(_ item: ClipItem, to pinboard: Pinboard) {
        do {
            try store.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
        }
    }
}

private struct PinboardCreateView: View {
    @Binding var name: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Pinboard")
                .font(.system(size: 14, weight: .semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                Spacer()
                Button("Create") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
