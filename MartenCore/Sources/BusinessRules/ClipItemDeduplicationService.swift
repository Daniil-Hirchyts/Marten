import CoreData
import Foundation

final class ClipItemDeduplicationService {
    func computeContentHash(
        primaryText: String?,
        representations: [ClipRepresentationPayload]
    ) throws -> String {
        let sortedRepresentations = representations.sorted { $0.displayOrder < $1.displayOrder }

        // Prefer binary payloads when present so placeholder labels like "Image"
        // do not collapse distinct media items onto the same hash.
        for representation in sortedRepresentations
        where representation.kind != .fileURL {
            if let data = representation.data, !data.isEmpty {
                return data.sha256Hex()
            }
        }

        if let primaryText, !primaryText.isEmpty {
            return Data(primaryText.utf8).sha256Hex()
        }

        for representation in sortedRepresentations {
            if let text = representation.text, !text.isEmpty {
                return Data(text.utf8).sha256Hex()
            }

            if let data = representation.data, !data.isEmpty {
                return data.sha256Hex()
            }
        }

        throw ClipItemStoreError.missingContent
    }

    func fetchExistingItem(hash: String, in context: NSManagedObjectContext) throws -> ClipItem? {
        let request = ClipItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@", hash)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

extension ClipItemDeduplicationService: Sendable {}

extension ClipItemDeduplicationService: ClipItemDeduplicationServicing {}
