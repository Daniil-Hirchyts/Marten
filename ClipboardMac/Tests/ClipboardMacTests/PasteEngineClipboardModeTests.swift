import AppKit
import ClipboardCore
import ClipboardMacServices
import XCTest

final class PasteEngineClipboardModeTests: XCTestCase {
    func testCopyItemToClipboardWritesPlainText() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Hello")

        let pasteboard = NSPasteboard.withUniqueName()
        let engine = PasteEngine(pasteboard: pasteboard)
        try await engine.copyItemToClipboard(item, format: PasteFormat.plainText)
        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "Hello")
    }

    func testCopyStackToClipboardJoinsItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let itemA = try store.createTextItem(text: "a")
        let itemB = try store.createTextItem(text: "b")

        let stackStore = StackSessionStore(persistence: persistence)
        let session = try stackStore.createSession()
        try stackStore.setEntries(
            sessionID: session.objectID, clipItemIDs: [itemA.objectID, itemB.objectID])
        let pasteboard = NSPasteboard.withUniqueName()
        let engine = PasteEngine(pasteboard: pasteboard)
        try await engine.copyStackToClipboard(session)
        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType.string), "a\nb")
    }

}
