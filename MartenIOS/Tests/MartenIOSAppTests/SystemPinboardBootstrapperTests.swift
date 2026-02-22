import CoreData
import MartenCore
@testable import MartenIOSApp
import XCTest

final class SystemPinboardBootstrapperTests: XCTestCase {
    private var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        persistence = nil
        super.tearDown()
    }

    // MARK: - Creation when none exists

    func testCreatesSystemPinboardWhenNoneExists() throws {
        let context = persistence.newBackgroundContext()
        let bootstrapper = SystemPinboardBootstrapper()

        let (survivingID, removedIDs) = try bootstrapper.ensureSystemPinboard(in: context)

        XCTAssertNotNil(survivingID, "Should return a surviving ID for the newly created pinboard")
        XCTAssertTrue(removedIDs.isEmpty, "No removals when creating fresh")

        var systemPinboards: [Pinboard] = []
        try context.performAndWaitThrowing {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == YES")
            systemPinboards = try context.fetch(request)
        }

        XCTAssertEqual(systemPinboards.count, 1)
        XCTAssertEqual(systemPinboards.first?.id, survivingID)
        XCTAssertEqual(systemPinboards.first?.name, "Marten")
        XCTAssertEqual(systemPinboards.first?.colorHex, "#808080")
        XCTAssertTrue(systemPinboards.first?.isSystemMarten == true)
    }

    // MARK: - Idempotency

    func testRunningTwiceIsIdempotent() throws {
        let context = persistence.newBackgroundContext()
        let bootstrapper = SystemPinboardBootstrapper()

        let (firstID, _) = try bootstrapper.ensureSystemPinboard(in: context)
        let (secondID, removedIDs) = try bootstrapper.ensureSystemPinboard(in: context)

        XCTAssertEqual(firstID, secondID, "Same pinboard should survive on second run")
        XCTAssertTrue(removedIDs.isEmpty, "Nothing to remove on second run")
    }

    // MARK: - Deduplication

    func testDeduplicatesMultipleSystemPinboards() throws {
        let context = persistence.newBackgroundContext()
        let bootstrapper = SystemPinboardBootstrapper()

        // Manually insert two system pinboards
        let (canonical, duplicate) = try insertTwoSystemPinboards(in: context)

        let (survivingID, removedIDs) = try bootstrapper.ensureSystemPinboard(in: context)

        XCTAssertEqual(survivingID, canonical.id, "Canonical (most items) should survive")
        XCTAssertTrue(removedIDs.contains(duplicate.id), "Duplicate should be in removedIDs")

        // Only one system pinboard should remain
        var remainingCount = 0
        try context.performAndWaitThrowing {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == YES")
            remainingCount = try context.fetch(request).count
        }
        XCTAssertEqual(remainingCount, 1)
    }

    func testKeepsCanonicalWithMostItems() throws {
        let context = persistence.newBackgroundContext()
        let bootstrapper = SystemPinboardBootstrapper()
        let store = ClipItemStore(persistence: persistence)

        // Create two system pinboards; add items to one to make it canonical
        let (canonical, duplicate) = try insertTwoSystemPinboards(in: context)

        // Add items to canonical via the main context (store operations use viewContext)
        let item1 = try store.createTextItem(text: "item 1", isUserCreated: true)
        let item2 = try store.createTextItem(text: "item 2", isUserCreated: true)
        try context.performAndWaitThrowing {
            guard let canonicalInBg = try context.existingObject(with: canonical.objectID) as? Pinboard,
                  let item1InBg = try? context.existingObject(with: item1.objectID) as? ClipItem,
                  let item2InBg = try? context.existingObject(with: item2.objectID) as? ClipItem
            else { return }
            canonicalInBg.addToItems(item1InBg)
            canonicalInBg.addToItems(item2InBg)
            try context.save()
        }

        let (survivingID, removedIDs) = try bootstrapper.ensureSystemPinboard(in: context)

        XCTAssertEqual(survivingID, canonical.id, "Pinboard with more items should be canonical")
        XCTAssertTrue(removedIDs.contains(duplicate.id))
    }

    func testItemsFromDuplicateAreMergedIntoCanonical() throws {
        let context = persistence.newBackgroundContext()
        let bootstrapper = SystemPinboardBootstrapper()
        let store = ClipItemStore(persistence: persistence)

        let (canonical, duplicate) = try insertTwoSystemPinboards(in: context)

        // Add an item to duplicate
        let item = try store.createTextItem(text: "orphan item", isUserCreated: true)
        try context.performAndWaitThrowing {
            guard let duplicateInBg = try context.existingObject(with: duplicate.objectID) as? Pinboard,
                  let itemInBg = try? context.existingObject(with: item.objectID) as? ClipItem
            else { return }
            duplicateInBg.addToItems(itemInBg)
            try context.save()
        }

        let (survivingID, _) = try bootstrapper.ensureSystemPinboard(in: context)
        XCTAssertEqual(survivingID, canonical.id)

        // The item should now belong to canonical
        var canonicalItemIDs: Set<UUID> = []
        try context.performAndWaitThrowing {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", canonical.id as NSUUID)
            request.fetchLimit = 1
            if let pinboard = try context.fetch(request).first {
                canonicalItemIDs = Set((pinboard.items ?? []).compactMap { $0.id })
            }
        }

        XCTAssertTrue(canonicalItemIDs.contains(item.id), "Item should be merged into canonical")
    }

    // MARK: - Surviving ID returned correctly

    func testSurvivingIDIsReturnedForExistingPinboard() throws {
        let context = persistence.newBackgroundContext()
        let bootstrapper = SystemPinboardBootstrapper()

        // First run creates it
        let (firstID, _) = try bootstrapper.ensureSystemPinboard(in: context)

        // Second run should return the same ID
        let (secondID, _) = try bootstrapper.ensureSystemPinboard(in: context)

        XCTAssertEqual(firstID, secondID)
    }

    // MARK: - Helpers

    private func insertTwoSystemPinboards(
        in context: NSManagedObjectContext
    ) throws -> (canonical: Pinboard, duplicate: Pinboard) {
        var canonical: Pinboard!
        var duplicate: Pinboard!

        try context.performAndWaitThrowing {
            let p1 = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as! Pinboard
            p1.id = UUID()
            p1.name = "Marten"
            p1.colorHex = "#808080"
            p1.sortOrder = 0
            p1.isSystemMarten = true
            p1.createdAt = Date(timeIntervalSinceReferenceDate: 1000)

            let p2 = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as! Pinboard
            p2.id = UUID()
            p2.name = "Marten Duplicate"
            p2.colorHex = "#808080"
            p2.sortOrder = 0
            p2.isSystemMarten = true
            p2.createdAt = Date(timeIntervalSinceReferenceDate: 2000)

            try context.save()
            canonical = p1  // p1 has earlier createdAt → canonical when item counts are equal
            duplicate = p2
        }

        return (canonical, duplicate)
    }
}
