import XCTest
@testable import ClipboardCore

final class StackSessionTests: XCTestCase {
    func testCreateSessionAndFetchActive() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = StackSessionStore(persistence: persistence)

        let session = try store.createSession(mode: .combined, separator: ", ")
        let active = try store.fetchActiveSession()

        XCTAssertEqual(active?.objectID, session.objectID)
        XCTAssertEqual(active?.modeValue, .combined)
        XCTAssertEqual(active?.separator, ", ")
        XCTAssertTrue(active?.isActive ?? false)
    }

    func testSetEntriesPersistsOrder() throws {
        let persistence = PersistenceController(inMemory: true)
        let itemStore = ClipItemStore(persistence: persistence)
        let stackStore = StackSessionStore(persistence: persistence)

        let first = try itemStore.createTextItem(text: "First")
        let second = try itemStore.createTextItem(text: "Second")
        let session = try stackStore.createSession()

        try stackStore.setEntries(sessionID: session.objectID, clipItemIDs: [second.objectID, first.objectID])

        let entries = try stackStore.fetchEntries(sessionID: session.objectID)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.clipItem?.objectID, second.objectID)
        XCTAssertEqual(entries.first?.position, 0)
        XCTAssertEqual(entries.last?.clipItem?.objectID, first.objectID)
        XCTAssertEqual(entries.last?.position, 1)
    }

    func testClearEntriesRemovesAll() throws {
        let persistence = PersistenceController(inMemory: true)
        let itemStore = ClipItemStore(persistence: persistence)
        let stackStore = StackSessionStore(persistence: persistence)

        let item = try itemStore.createTextItem(text: "Only")
        let session = try stackStore.createSession()
        try stackStore.setEntries(sessionID: session.objectID, clipItemIDs: [item.objectID])

        try stackStore.clearEntries(sessionID: session.objectID)
        let entries = try stackStore.fetchEntries(sessionID: session.objectID)
        XCTAssertTrue(entries.isEmpty)
    }
}
