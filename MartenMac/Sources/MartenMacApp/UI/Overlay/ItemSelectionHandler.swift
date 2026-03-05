import MartenCore
import CoreData

struct ItemSelectionUpdate {
    let selectedIDs: Set<NSManagedObjectID>
    let anchorID: NSManagedObjectID?
    let cursorID: NSManagedObjectID?
}

struct ItemSelectionHandler {
    func updatedSelection(
        currentSelection: Set<NSManagedObjectID>,
        currentAnchorID: NSManagedObjectID?,
        currentCursorID: NSManagedObjectID?,
        orderedItems: [ClipItem],
        tappedItem: ClipItem,
        isShiftPressed: Bool,
        isCommandPressed: Bool
    ) -> ItemSelectionUpdate {
        let tappedID = tappedItem.objectID
        let orderedIDs = orderedItems.map(\.objectID)

        func index(of objectID: NSManagedObjectID?) -> Int? {
            guard let objectID else { return nil }
            return orderedIDs.firstIndex(of: objectID)
        }

        func firstSelectedID(in selection: Set<NSManagedObjectID>) -> NSManagedObjectID? {
            orderedIDs.first(where: { selection.contains($0) })
        }

        func singleSelectionResult(_ objectID: NSManagedObjectID) -> ItemSelectionUpdate {
            ItemSelectionUpdate(
                selectedIDs: [objectID],
                anchorID: objectID,
                cursorID: objectID
            )
        }

        guard index(of: tappedID) != nil else {
            return ItemSelectionUpdate(
                selectedIDs: currentSelection,
                anchorID: currentAnchorID,
                cursorID: currentCursorID
            )
        }

        if isShiftPressed {
            let resolvedAnchorID =
                (index(of: currentAnchorID) != nil ? currentAnchorID : nil)
                ?? (index(of: currentCursorID) != nil ? currentCursorID : nil)
                ?? firstSelectedID(in: currentSelection)
                ?? tappedID

            guard let anchorIndex = index(of: resolvedAnchorID),
                let tappedIndex = index(of: tappedID)
            else {
                return singleSelectionResult(tappedID)
            }

            let start = min(anchorIndex, tappedIndex)
            let end = max(anchorIndex, tappedIndex)
            let rangeSelection = Set(orderedIDs[start...end])

            let nextSelection =
                isCommandPressed
                ? currentSelection.union(rangeSelection)
                : rangeSelection

            return ItemSelectionUpdate(
                selectedIDs: nextSelection,
                anchorID: resolvedAnchorID,
                cursorID: tappedID
            )
        }

        if isCommandPressed {
            var nextSelection = currentSelection
            if nextSelection.contains(tappedID) {
                nextSelection.remove(tappedID)
            } else {
                nextSelection.insert(tappedID)
            }

            guard !nextSelection.isEmpty else {
                return ItemSelectionUpdate(selectedIDs: [], anchorID: nil, cursorID: nil)
            }

            let endpointID: NSManagedObjectID
            if nextSelection.contains(tappedID) {
                endpointID = tappedID
            } else if let currentCursorID, nextSelection.contains(currentCursorID) {
                endpointID = currentCursorID
            } else if let fallbackID = firstSelectedID(in: nextSelection) {
                endpointID = fallbackID
            } else {
                endpointID = tappedID
            }

            return ItemSelectionUpdate(
                selectedIDs: nextSelection,
                anchorID: endpointID,
                cursorID: endpointID
            )
        }

        return singleSelectionResult(tappedID)
    }
}
