import CoreData
import XCTest

@testable import ClipboardCore

final class PerformanceBenchmarks: XCTestCase {
    func testSearchPerformance() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let totalItems = 1_000
        for index in 0..<totalItems {
            let marker = index.isMultiple(of: 10) ? "Needle" : "Hay"
            _ = try store.createTextItem(text: "Item \(index) \(marker)")
        }

        measure {
            do {
                _ = try store.searchItems(query: "needle")
            } catch {
                XCTFail("Search failed: \(error)")
            }
        }
    }

    func testRetentionCleanupPerformance() {
        let totalItems = 1_000
        let expiredItems = 700
        let now = Date()
        let expiredDate = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            let persistence = PersistenceController(inMemory: true)
            let store = ClipItemStore(persistence: persistence)

            var objectIDs: [NSManagedObjectID] = []
            objectIDs.reserveCapacity(totalItems)
            for index in 0..<totalItems {
                do {
                    let item = try store.createTextItem(text: "Item \(index)")
                    objectIDs.append(item.objectID)
                } catch {
                    XCTFail("Seed failed: \(error)")
                    return
                }
            }

            let context = persistence.viewContext
            do {
                try context.performAndWaitThrowing {
                    for (index, objectID) in objectIDs.enumerated() {
                        guard let item = try context.existingObject(with: objectID) as? ClipItem
                        else {
                            continue
                        }
                        let date = index < expiredItems ? expiredDate : now
                        item.createdAt = date
                        item.modifiedAt = date
                    }
                    try context.save()
                }
            } catch {
                XCTFail("Date update failed: \(error)")
                return
            }

            startMeasuring()
            do {
                _ = try store.cleanupExpiredItems(policy: .week, now: now)
            } catch {
                XCTFail("Cleanup failed: \(error)")
            }
            stopMeasuring()
        }
    }

    func testHashingPerformance() {
        let data = Data(repeating: 0xA5, count: 512 * 1024)

        measure {
            _ = data.sha256Hex()
        }
    }

    func testDedupedInsertPerformance() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        _ = try store.createTextItem(text: "Duplicate payload")

        measure {
            do {
                for _ in 0..<25 {
                    _ = try store.createTextItem(text: "Duplicate payload")
                }
            } catch {
                XCTFail("Dedupe insert failed: \(error)")
            }
        }
    }
}
