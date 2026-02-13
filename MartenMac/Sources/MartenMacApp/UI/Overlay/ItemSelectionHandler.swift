import MartenCore
import CoreData

struct ItemSelectionHandler {
    func updatedSelection(
        currentSelection: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        tappedItem: ClipItem,
        isShiftPressed: Bool,
        isCommandPressed: Bool
    ) -> Set<NSManagedObjectID> {
        if isShiftPressed {
            guard let anchorID = currentSelection.first,
                let anchorIndex = orderedItems.firstIndex(where: { $0.objectID == anchorID }),
                let currentIndex = orderedItems.firstIndex(where: { $0.objectID == tappedItem.objectID })
            else {
                return [tappedItem.objectID]
            }

            let start = min(anchorIndex, currentIndex)
            let end = max(anchorIndex, currentIndex)

            var nextSelection = currentSelection
            nextSelection.formUnion(orderedItems[start...end].map { $0.objectID })
            return nextSelection
        }

        if isCommandPressed {
            var nextSelection = currentSelection
            if nextSelection.contains(tappedItem.objectID) {
                nextSelection.remove(tappedItem.objectID)
            } else {
                nextSelection.insert(tappedItem.objectID)
            }
            return nextSelection
        }

        // Multi-select mode: toggle tapped item in/out of selection
        if currentSelection.count > 1 {
            var next = currentSelection
            if next.contains(tappedItem.objectID) {
                next.remove(tappedItem.objectID)
            } else {
                next.insert(tappedItem.objectID)
            }
            return next
        }

        if currentSelection.count == 1 && currentSelection.contains(tappedItem.objectID) {
            return []
        }

        return [tappedItem.objectID]
    }
}

