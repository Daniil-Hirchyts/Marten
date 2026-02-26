import CoreData
import Foundation

public protocol PinboardRepositoryProtocol: Sendable {
    func fetchPinboards() throws -> [Pinboard]

    @discardableResult
    func createPinboard(name: String, colorHex: String, iconName: String?) throws -> Pinboard

    func renamePinboard(objectID: NSManagedObjectID, name: String, colorHex: String?) throws
    func updatePinboard(objectID: NSManagedObjectID, name: String, colorHex: String, iconName: String?)
        throws
    func deletePinboard(objectID: NSManagedObjectID) throws
    func deleteUserPinboards() throws

    func addItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID) throws
    func removeItem(objectID: NSManagedObjectID, fromPinboard pinboardID: NSManagedObjectID) throws
    func moveItem(objectID: NSManagedObjectID, toPinboard pinboardID: NSManagedObjectID) throws
    func moveItems(objectIDs: [NSManagedObjectID], toPinboard pinboardID: NSManagedObjectID) throws
    func reorderPinboards(orderedIDs: [NSManagedObjectID]) throws

    func fetchOrCreateSystemMartenPinboard(in context: NSManagedObjectContext) throws -> Pinboard
}

public extension PinboardRepositoryProtocol {
    func createPinboard(name: String, colorHex: String) throws -> Pinboard {
        try createPinboard(name: name, colorHex: colorHex, iconName: nil)
    }

    func renamePinboard(objectID: NSManagedObjectID, name: String) throws {
        try renamePinboard(objectID: objectID, name: name, colorHex: nil)
    }
}
