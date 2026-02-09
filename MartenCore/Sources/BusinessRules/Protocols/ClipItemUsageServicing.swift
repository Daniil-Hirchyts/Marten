import CoreData
import Foundation

public protocol ClipItemUsageServicing: Sendable {
    func markItemUsed(objectID: NSManagedObjectID, now: Date) throws
    func markItemsUsed(objectIDs: [NSManagedObjectID], now: Date) throws
    func reorderItems(objectIDs: [NSManagedObjectID]) throws
}

public extension ClipItemUsageServicing {
    func markItemUsed(objectID: NSManagedObjectID) throws {
        try markItemUsed(objectID: objectID, now: Date())
    }

    func markItemsUsed(objectIDs: [NSManagedObjectID]) throws {
        try markItemsUsed(objectIDs: objectIDs, now: Date())
    }
}
