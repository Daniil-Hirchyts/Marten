import MartenCore
import CoreData
import OSLog

@MainActor
final class PinboardManager {
    private let store: ClipItemStore
    private let persistence: PersistenceController

    init(store: ClipItemStore, persistence: PersistenceController) {
        self.store = store
        self.persistence = persistence
    }

    convenience init(services: any CaptureServicesProviding) {
        self.init(store: services.clipItemStore, persistence: services.persistence)
    }

    func deletePinboard(_ pinboard: Pinboard, selectedPinboardID: UUID?) -> UUID? {
        guard !pinboard.isSystemMarten else { return selectedPinboardID }
        let updatedSelection: UUID? = selectedPinboardID == pinboard.id ? nil : selectedPinboardID
        do {
            try store.deletePinboard(objectID: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to delete pinboard: \(error.localizedDescription)")
        }
        return updatedSelection
    }

    func renamePinboard(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) -> Bool {
        do {
            try store.updatePinboard(
                objectID: objectID,
                name: name,
                colorHex: colorHex,
                iconName: iconName
            )
            return true
        } catch {
            Logger.app.error("Failed to rename pinboard: \(error.localizedDescription)")
            return false
        }
    }

    func createPinboard(
        name: String,
        colorHex: String,
        iconName: String? = nil,
        pendingItem: ClipItem?
    ) -> Bool {
        do {
            let pinboard = try store.createPinboard(name: name, colorHex: colorHex, iconName: iconName)
            if let pendingItem {
                try? store.moveItem(objectID: pendingItem.objectID, toPinboard: pinboard.objectID)
            }
            return true
        } catch {
            Logger.app.error("Failed to create pinboard: \(error.localizedDescription)")
            return false
        }
    }

    func changePinboardColor(_ pinboard: Pinboard, hex: String) {
        do {
            try store.updatePinboard(
                objectID: pinboard.objectID,
                name: pinboard.name,
                colorHex: hex,
                iconName: pinboard.iconName
            )
        } catch {
            Logger.app.error("Failed to change pinboard color: \(error.localizedDescription)")
        }
    }

    func changePinboardIcon(_ pinboard: Pinboard, iconName: String?) {
        do {
            try store.updatePinboard(
                objectID: pinboard.objectID,
                name: pinboard.name,
                colorHex: pinboard.colorHex,
                iconName: iconName
            )
        } catch {
            Logger.app.error("Failed to change pinboard icon: \(error.localizedDescription)")
        }
    }

    func moveItem(_ item: ClipItem, to pinboard: Pinboard) {
        do {
            try store.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
        }
    }

    func toggleItem(_ item: ClipItem, in pinboard: Pinboard) {
        let isAssigned =
            item.pinboards?.contains(where: { $0.objectID == pinboard.objectID }) ?? false
        do {
            if isAssigned {
                try store.removeItem(objectID: item.objectID, fromPinboard: pinboard.objectID)
            } else {
                try store.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)
            }
        } catch {
            Logger.app.error("Failed to toggle item pinboard: \(error.localizedDescription)")
        }
    }

    func moveItemToPinboard(_ pinboard: Pinboard, itemURIString: String) {
        guard let url = URL(string: itemURIString),
            let objectID = persistence.container.persistentStoreCoordinator
                .managedObjectID(forURIRepresentation: url)
        else { return }

        do {
            try store.moveItem(objectID: objectID, toPinboard: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
        }
    }

    func handleDropToPinboard(item: ClipItem, pinboardID: NSManagedObjectID) -> Bool {
        do {
            try store.moveItem(objectID: item.objectID, toPinboard: pinboardID)
            return true
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
            return false
        }
    }

    func handleDropToAll(item: ClipItem, selectedPinboard: Pinboard?) -> Bool {
        guard let selectedPinboard else { return false }
        do {
            try store.removeItem(objectID: item.objectID, fromPinboard: selectedPinboard.objectID)
            return true
        } catch {
            Logger.app.error("Failed to remove item from pinboard: \(error.localizedDescription)")
            return false
        }
    }

    func optimisticReorderPinboards(
        dragged: Pinboard, target: Pinboard, insertBefore: Bool, visiblePinboards: [Pinboard]
    ) {
        guard !dragged.isSystemMarten, !target.isSystemMarten else { return }

        var ordered = visiblePinboards
        guard let fromIndex = ordered.firstIndex(where: { $0.objectID == dragged.objectID }),
            var toIndex = ordered.firstIndex(where: { $0.objectID == target.objectID }),
            fromIndex != toIndex
        else { return }

        if !insertBefore {
            toIndex += 1
        }

        let movedItem = ordered.remove(at: fromIndex)

        let adjustedIndex: Int
        if fromIndex < toIndex {
            adjustedIndex = toIndex - 1
        } else {
            adjustedIndex = toIndex
        }

        ordered.insert(movedItem, at: adjustedIndex)

        for (index, pinboard) in ordered.enumerated() {
            pinboard.sortOrder = Int16(index)
        }
    }

    func saveChanges() {
        do {
            try store.saveChanges()
        } catch {
            Logger.app.error("Failed to save reorder: \(error.localizedDescription)")
        }
    }

    // MARK: - Share / Lock Mutual Exclusivity

    /// Returns whether a pinboard can be shared (not locked, not system).
    func canSharePinboard(_ pinboard: Pinboard, isLocked: Bool) -> Bool {
        !pinboard.isSystemMarten && !isLocked
    }

    /// Returns whether a pinboard can be locked (not shared).
    func canLockPinboard(_ pinboard: Pinboard) -> Bool {
        !pinboard.isShared
    }
}
