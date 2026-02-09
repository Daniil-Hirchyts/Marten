import CoreData
import Foundation

public protocol ClipItemDeduplicationServicing: Sendable {
    func computeContentHash(primaryText: String?, representations: [ClipRepresentationPayload]) throws
        -> String

    func fetchExistingItem(hash: String, in context: NSManagedObjectContext) throws -> ClipItem?
}
