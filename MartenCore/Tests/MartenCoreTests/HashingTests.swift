import CoreData
import XCTest
@testable import MartenCore

final class HashingTests: XCTestCase {
    func testSHA256HexIsStableAndLength64() {
        let data = Data("hash me".utf8)
        let first = data.sha256Hex()
        let second = data.sha256Hex()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    func testCanonicalHashUsesPrimaryText() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        guard let item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as? ClipItem else {
            XCTFail("Failed to insert ClipItem")
            return
        }
        item.id = UUID()
        item.createdAt = Date()
        item.modifiedAt = Date()
        item.primaryText = "Hello"
        item.contentHash = ""

        let hash = try item.computeCanonicalHash()
        XCTAssertEqual(hash.count, 64)
    }
}
