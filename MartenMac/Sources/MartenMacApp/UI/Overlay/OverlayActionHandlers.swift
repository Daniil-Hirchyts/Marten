@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import CoreData
import SwiftUI

/// Consolidated action handlers for overlay operations
@MainActor
struct OverlayActionHandlers {
    let itemOperationsHandler: any ItemOperating
    let pinboardManager: any PinboardManaging
    let pasteStackManager: PasteStackManager
    let pinboardLockController: PinboardLockController
    let searchModel: OverlaySearchViewModel

    // MARK: - Item Operations

    func copyItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        filteredItems: [ClipItem],
        eventBroadcaster: any MartenEventBroadcaster
    ) {
        itemOperationsHandler.copyItem(
            item,
            selectedItemIDs: selectedItemIDs,
            orderedItems: filteredItems,
            eventBroadcaster: eventBroadcaster
        )
    }

    func deleteItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        onClearSelection: @escaping () -> Void
    ) {
        itemOperationsHandler.deleteItem(
            item,
            selectedItemIDs: selectedItemIDs,
            onClearSelection: onClearSelection
        )
    }

    func commitItemRename(item: ClipItem, newTitle: String) {
        itemOperationsHandler.commitItemRename(itemID: item.objectID, newTitle: newTitle)
    }

    func togglePin(_ item: ClipItem, allowPinning: Bool) {
        itemOperationsHandler.togglePin(item, allowPinning: allowPinning)
    }

    // MARK: - Pinboard Operations

    func deletePinboard(_ pinboard: Pinboard, selectedPinboardID: UUID?) -> UUID? {
        let newID = pinboardManager.deletePinboard(
            pinboard,
            selectedPinboardID: selectedPinboardID
        )
        pinboardLockController.setLockEnabled(false, pinboardID: pinboard.id)
        return newID
    }

    func commitPinboardRename(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        return pinboardManager.renamePinboard(
            objectID: objectID,
            name: trimmedName,
            colorHex: colorHex,
            iconName: iconName
        )
    }

    func commitPinboardCreate(
        name: String,
        colorHex: String,
        iconName: String?,
        pendingItem: ClipItem?
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        return pinboardManager.createPinboard(
            name: trimmedName,
            colorHex: colorHex,
            iconName: iconName,
            pendingItem: pendingItem
        )
    }

    func handleMoveToPinboard(_ item: ClipItem, _ pinboard: Pinboard) {
        guard pinboardLockController.canAccess(pinboardID: pinboard.id) else { return }
        pinboardManager.toggleItem(item, in: pinboard)
    }

    // MARK: - Drag & Drop

    func handleDropToPinboard(
        _ item: ClipItem,
        _ pinboardID: NSManagedObjectID,
        pinboards: FetchedResults<Pinboard>,
        onClearSelection: @escaping () -> Void
    ) {
        guard let targetPinboard = pinboards.first(where: { $0.objectID == pinboardID }) else {
            return
        }
        guard pinboardLockController.canAccess(pinboardID: targetPinboard.id) else {
            return
        }

        if pinboardManager.handleDropToPinboard(item: item, pinboardID: pinboardID) {
            onClearSelection()
            if searchModel.isSearchTextActive {
                searchModel.refreshSearchNow()
            }
        }
    }

    func handleDropToAll(
        _ item: ClipItem,
        selectedPinboardID: UUID?,
        pinboards: FetchedResults<Pinboard>,
        onClearSelection: @escaping () -> Void
    ) {
        let selectedPinboard = selectedPinboardID.flatMap { id in
            pinboards.first(where: { $0.id == id })
        }

        if pinboardManager.handleDropToAll(item: item, selectedPinboard: selectedPinboard) {
            onClearSelection()
        }
    }

    // MARK: - Item Reordering

    func reorderItems(
        _ draggedIDs: [NSManagedObjectID],
        _ target: ClipItem,
        insertBefore: Bool,
        filteredItems: [ClipItem],
        isSearchActive: Bool
    ) {
        guard !isSearchActive else { return }

        var ordered = filteredItems

        let draggedItems = draggedIDs.compactMap { id in
            ordered.first { $0.objectID == id }
        }

        ordered.removeAll { item in
            draggedIDs.contains(item.objectID)
        }

        guard var targetIndex = ordered.firstIndex(where: { $0.objectID == target.objectID }) else {
            return
        }

        if !insertBefore {
            targetIndex += 1
        }

        ordered.insert(contentsOf: draggedItems, at: targetIndex)

        let now = Date()
        let baseOrder = Int64(now.timeIntervalSince1970 * 1000) + Int64(ordered.count)

        for (index, item) in ordered.enumerated() {
            item.displayOrder = baseOrder - Int64(index)
        }
    }

    // MARK: - Sorting

    func sortItems(_ items: [ClipItem], selectedPinboardID: UUID?, allowPinning: Bool) -> [ClipItem] {
        guard selectedPinboardID != nil else {
            // In "All" view, sort by displayOrder (most recently used first)
            return items.sorted { lhs, rhs in
                if lhs.displayOrder != rhs.displayOrder {
                    return lhs.displayOrder > rhs.displayOrder
                }
                return lhs.createdAt > rhs.createdAt
            }
        }

        return items.sorted { lhs, rhs in
            if allowPinning, lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder > rhs.displayOrder
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
