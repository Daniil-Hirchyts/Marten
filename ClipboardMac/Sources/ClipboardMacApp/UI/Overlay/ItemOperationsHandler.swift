import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import CoreData
import OSLog

@MainActor
final class ItemOperationsHandler {
    private let store: ClipItemStore
    private let pasteboard: NSPasteboard
    private let soundPlayer = SoundEffectPlayer()

    init(store: ClipItemStore = ClipItemStore(), pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
    }

    func copyItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        eventBroadcaster: any ClipboardEventBroadcaster
    ) {
        if selectedItemIDs.count > 1 && selectedItemIDs.contains(item.objectID) {
            copySelectedItems(
                selectedItemIDs: selectedItemIDs,
                orderedItems: orderedItems,
                eventBroadcaster: eventBroadcaster
            )
            return
        }

        guard let text = item.primaryText, !text.isEmpty else { return }
        eventBroadcaster.publish(.clipboardWillWrite)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func deleteItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        onClearSelection: () -> Void
    ) {
        if selectedItemIDs.count > 1 && selectedItemIDs.contains(item.objectID) {
            deleteSelectedItems(
                selectedItemIDs: selectedItemIDs, onClearSelection: onClearSelection)
            return
        }

        do {
            try store.deleteItem(objectID: item.objectID)
            soundPlayer.play(.delete)
        } catch {
            Logger.app.error("Failed to delete item: \(error.localizedDescription)")
        }
    }

    func commitItemRename(itemID: NSManagedObjectID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.renameItem(objectID: itemID, title: trimmed.isEmpty ? nil : trimmed)
        } catch {
            Logger.app.error("Failed to rename item: \(error.localizedDescription)")
        }
    }

    func togglePin(_ item: ClipItem, allowPinning: Bool) {
        guard allowPinning else { return }
        let context = item.managedObjectContext
        context?.performAndWait {
            item.isPinned.toggle()
            if item.isPinned {
                item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
            }
            do {
                try context?.save()
            } catch {
                Logger.app.error("Failed to toggle pin: \(error.localizedDescription)")
            }
        }
    }

    private func copySelectedItems(
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        eventBroadcaster: any ClipboardEventBroadcaster
    ) {
        let selectedItems = orderedItems.filter { selectedItemIDs.contains($0.objectID) }
        let texts = selectedItems.compactMap { $0.primaryText }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }

        eventBroadcaster.publish(.clipboardWillWrite)
        pasteboard.clearContents()
        pasteboard.setString(texts.joined(separator: "\n"), forType: .string)
    }

    private func deleteSelectedItems(
        selectedItemIDs: Set<NSManagedObjectID>,
        onClearSelection: () -> Void
    ) {
        let idsToDelete = Array(selectedItemIDs)
        onClearSelection()
        for objectID in idsToDelete {
            do {
                try store.deleteItem(objectID: objectID)
            } catch {
                Logger.app.error("Failed to delete item: \(error.localizedDescription)")
            }
        }
        if !idsToDelete.isEmpty {
            soundPlayer.play(.delete)
        }
    }
}
