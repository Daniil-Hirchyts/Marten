import XCTest
@testable import MartenCore

final class ModelComputedPropertiesTests: XCTestCase {
    func testItemTypeValueSetAndRead() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        var item: ClipItem?
        try context.performAndWaitThrowing {
            item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as? ClipItem
            item?.itemTypeValue = .richText
        }

        XCTAssertEqual(item?.itemTypeValue, .text)
    }

    func testHasMultipleRepresentations() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        var item: ClipItem?
        try context.performAndWaitThrowing {
            item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as? ClipItem
            let rep1 = NSEntityDescription.insertNewObject(forEntityName: "ClipRepresentation", into: context) as? ClipRepresentation
            rep1?.id = UUID()
            rep1?.uti = "public.utf8-plain-text"
            rep1?.kindValue = .plainText
            rep1?.displayOrder = 0
            rep1?.clipItem = item

            let rep2 = NSEntityDescription.insertNewObject(forEntityName: "ClipRepresentation", into: context) as? ClipRepresentation
            rep2?.id = UUID()
            rep2?.uti = "public.rtf"
            rep2?.kindValue = .rtf
            rep2?.displayOrder = 1
            rep2?.clipItem = item

            if let rep1, let rep2 {
                item?.addToRepresentations(Set([rep1, rep2]))
            }
        }

        XCTAssertEqual(item?.hasMultipleRepresentations, true)
    }

    func testComputeCanonicalHashUsesPrimaryText() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        var computed: String?
        try context.performAndWaitThrowing {
            let item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as? ClipItem
            item?.primaryText = "Hello World"
            computed = try item?.computeCanonicalHash()
        }

        let expected = Data("Hello World".utf8).sha256Hex()
        XCTAssertEqual(computed, expected)
    }

    func testComputeCanonicalHashFallsBackToTextData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        var computed: String?
        try context.performAndWaitThrowing {
            let item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as? ClipItem

            let rep = NSEntityDescription.insertNewObject(forEntityName: "ClipRepresentation", into: context) as? ClipRepresentation
            rep?.id = UUID()
            rep?.uti = "public.utf8-plain-text"
            rep?.kindValue = .plainText
            rep?.displayOrder = 0
            rep?.textData = Data("Fallback".utf8)
            rep?.clipItem = item

            if let rep {
                item?.addToRepresentations(rep)
            }

            computed = try item?.computeCanonicalHash()
        }

        let expected = Data("Fallback".utf8).sha256Hex()
        XCTAssertEqual(computed, expected)
    }

    func testClipRepresentationKindValue() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        var representation: ClipRepresentation?
        try context.performAndWaitThrowing {
            representation = NSEntityDescription.insertNewObject(forEntityName: "ClipRepresentation", into: context) as? ClipRepresentation
            representation?.kindValue = .jpeg
        }

        XCTAssertEqual(representation?.kindValue, .jpeg)
    }

    func testPinboardItemCount() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext

        var pinboard: Pinboard?
        try context.performAndWaitThrowing {
            pinboard = NSEntityDescription.insertNewObject(forEntityName: "Pinboard", into: context) as? Pinboard
            let item = NSEntityDescription.insertNewObject(forEntityName: "ClipItem", into: context) as? ClipItem
            if let item {
                pinboard?.addToItems(item)
            }
        }

        XCTAssertEqual(pinboard?.itemCount, 1)
    }
}
