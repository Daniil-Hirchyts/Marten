import CoreData
import Foundation
import MartenCore

public actor ClipItemCommandService {
    private let store: ClipItemStore

    public init(store: ClipItemStore) {
        self.store = store
    }

    public func createTextItem(
        text: String,
        sourceApp: SourceAppInfo?,
        isUserCreated: Bool
    ) throws {
        _ = try store.createTextItem(
            text: text,
            sourceApp: sourceApp,
            isUserCreated: isUserCreated
        )
    }

    public func createItem(
        payload: ClipItemPayload,
        sourceApp: SourceAppInfo?,
        isUserCreated: Bool
    ) throws {
        _ = try store.createItem(
            payload: payload,
            sourceApp: sourceApp,
            isUserCreated: isUserCreated
        )
    }

    public func createPinboard(name: String, colorHex: String, iconName: String?) throws {
        _ = try store.createPinboard(name: name, colorHex: colorHex, iconName: iconName)
    }

    public func updatePinboard(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) throws {
        try store.updatePinboard(
            objectID: objectID,
            name: name,
            colorHex: colorHex,
            iconName: iconName
        )
    }

    public func deletePinboard(objectID: NSManagedObjectID) throws {
        try store.deletePinboard(objectID: objectID)
    }

    public func deleteItem(objectID: NSManagedObjectID) throws {
        try store.deleteItem(objectID: objectID)
    }

    public func markItemUsed(objectID: NSManagedObjectID) throws {
        try store.markItemUsed(objectID: objectID)
    }

    public func markItemsUsed(objectIDs: [NSManagedObjectID]) throws {
        try store.markItemsUsed(objectIDs: objectIDs)
    }

    public func addItem(objectID: NSManagedObjectID, to pinboardID: NSManagedObjectID) throws {
        try store.addItem(objectID: objectID, toPinboard: pinboardID)
    }

    public func removeItem(objectID: NSManagedObjectID, from pinboardID: NSManagedObjectID) throws {
        try store.removeItem(objectID: objectID, fromPinboard: pinboardID)
    }

    public func removeItems(objectIDs: [NSManagedObjectID], fromPinboardID pinboardID: NSManagedObjectID)
        throws
    {
        guard !objectIDs.isEmpty else { return }
        for objectID in objectIDs {
            try store.removeItem(objectID: objectID, fromPinboard: pinboardID)
        }
    }

    public func moveItem(objectID: NSManagedObjectID, to pinboardID: NSManagedObjectID) throws {
        try store.moveItem(objectID: objectID, toPinboard: pinboardID)
    }

    public func moveItems(objectIDs: [NSManagedObjectID], toPinboardID pinboardID: NSManagedObjectID)
        throws
    {
        guard !objectIDs.isEmpty else { return }
        try store.moveItems(objectIDs: objectIDs, toPinboard: pinboardID)
    }

    public func reorderPinboards(orderedIDs: [NSManagedObjectID]) throws {
        try store.reorderPinboards(orderedIDs: orderedIDs)
    }

    public func deleteItems(objectIDs: [NSManagedObjectID]) throws {
        guard !objectIDs.isEmpty else { return }
        for objectID in objectIDs {
            try store.deleteItem(objectID: objectID)
        }
    }

    public func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data)
        throws
    {
        _ = try store.updateRichTextItem(
            objectID: objectID,
            newText: newText,
            rtfData: rtfData
        )
    }
}
