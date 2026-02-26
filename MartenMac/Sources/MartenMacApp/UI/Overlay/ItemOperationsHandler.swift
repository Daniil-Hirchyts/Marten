import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import CoreData
import OSLog

@MainActor
final class ItemOperationsHandler {
    private let store: ClipItemStore
    private let pasteboard: NSPasteboard
    private let soundPlayer: SoundEffectPlayer

    init(store: ClipItemStore, soundPlayer: SoundEffectPlayer, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.soundPlayer = soundPlayer
        self.pasteboard = pasteboard
    }

    func copyItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        eventBroadcaster: any MartenEventBroadcaster
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
        soundPlayer.play(.copy)

        do {
            try store.markItemUsed(objectID: item.objectID)
        } catch {
            Logger.app.error("Failed to mark copied item as used: \(error.localizedDescription)")
        }
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

    func updateImageData(itemID: NSManagedObjectID, imageData: Data) {
        do {
            try store.updateImageData(objectID: itemID, imageData: imageData)
        } catch {
            Logger.app.error("Failed to update image: \(error.localizedDescription)")
        }
    }

    func updateFileName(itemID: NSManagedObjectID, newFileName: String) {
        let trimmed = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.updateFileName(objectID: itemID, newFileName: trimmed)
        } catch {
            Logger.app.error("Failed to update file name: \(error.localizedDescription)")
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

    func convertItemType(_ item: ClipItem, to newType: ItemType) {
        do {
            _ = try store.updateItemType(objectID: item.objectID, newType: newType)
        } catch {
            Logger.app.error("Failed to convert item type: \(error.localizedDescription)")
        }
    }

    private func copySelectedItems(
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        eventBroadcaster: any MartenEventBroadcaster
    ) {
        let selectedItems = orderedItems.filter { selectedItemIDs.contains($0.objectID) }
        let itemsToCopy = selectedItems.filter { ($0.primaryText?.isEmpty == false) }
        let texts = itemsToCopy.compactMap { $0.primaryText }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }

        eventBroadcaster.publish(.clipboardWillWrite)
        pasteboard.clearContents()
        pasteboard.setString(texts.joined(separator: "\n"), forType: .string)
        soundPlayer.play(.copy)

        let ids = itemsToCopy.map(\.objectID)
        do {
            try store.markItemsUsed(objectIDs: ids)
        } catch {
            Logger.app.error(
                "Failed to mark copied items as used: \(error.localizedDescription)")
        }
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
