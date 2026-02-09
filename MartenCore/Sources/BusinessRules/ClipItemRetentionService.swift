import Foundation

final class ClipItemRetentionService {
    private let persistence: PersistenceController
    private let assetManagementService: AssetManagementService

    init(
        persistence: PersistenceController = .shared,
        assetManagementService: AssetManagementService
    ) {
        self.persistence = persistence
        self.assetManagementService = assetManagementService
    }

    func cleanupExpiredItems(policy: RetentionPolicy, now: Date = Date()) throws -> Int {
        guard let retentionDate = policy.retentionDate(reference: now) else {
            return 0
        }

        let context = persistence.newBackgroundContext()
        var deletedCount = 0

        try context.performAndWaitThrowing {
            let request = ClipItem.fetchRequest()
            request.predicate = NSPredicate(
                format:
                    "createdAt < %@ AND isPinned == NO AND SUBQUERY(pinboards, $p, $p.isSystemMarten == NO).@count == 0",
                retentionDate as NSDate
            )

            let expiredItems = try context.fetch(request)
            deletedCount = expiredItems.count
            let cleanupPlans = expiredItems.map { assetManagementService.makeAssetCleanupPlan(for: $0) }

            for item in expiredItems {
                context.delete(item)
            }

            if context.hasChanges {
                try context.save()
            }

            for plan in cleanupPlans {
                assetManagementService.executeAssetCleanupPlan(plan)
            }
        }

        return deletedCount
    }
}

// SAFETY: ClipItemRetentionService is immutable after initialization. All Core Data mutations are
// performed on a private background context via `performAndWaitThrowing`.
extension ClipItemRetentionService: @unchecked Sendable {}

extension ClipItemRetentionService: ClipItemRetentionServicing {}
