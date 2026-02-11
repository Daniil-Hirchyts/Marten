import CoreData
import MartenCore
import Observation

@MainActor
@Observable
final class DashboardSelectionModel {
    var isSelectionMode = false {
        didSet {
            if !isSelectionMode {
                clearSelection()
            }
        }
    }

    var selectedObjectIDs: Set<NSManagedObjectID> = []

    var selectedCount: Int {
        selectedObjectIDs.count
    }

    var hasSelection: Bool {
        !selectedObjectIDs.isEmpty
    }

    func toggleSelectionMode() {
        isSelectionMode.toggle()
    }

    func clearSelection() {
        selectedObjectIDs.removeAll()
    }

    func isSelected(_ item: ClipItem) -> Bool {
        selectedObjectIDs.contains(item.objectID)
    }

    func toggleSelection(for item: ClipItem) {
        if selectedObjectIDs.contains(item.objectID) {
            selectedObjectIDs.remove(item.objectID)
        } else {
            selectedObjectIDs.insert(item.objectID)
        }
    }

    func setSelection(_ objectIDs: [NSManagedObjectID]) {
        selectedObjectIDs = Set(objectIDs)
    }

    func dragPayload(for item: ClipItem) -> ItemDragPayload {
        if isSelectionMode,
            selectedObjectIDs.contains(item.objectID),
            !selectedObjectIDs.isEmpty
        {
            return ItemDragPayload(objectIDs: Array(selectedObjectIDs))
        }

        return ItemDragPayload(objectIDs: [item.objectID])
    }

    func resolveObjectIDs(
        from payload: ItemDragPayload,
        coordinator: NSPersistentStoreCoordinator
    ) -> [NSManagedObjectID] {
        payload.objectIDURIs.compactMap {
            coordinator.managedObjectID(forURIRepresentation: $0)
        }
    }
}
