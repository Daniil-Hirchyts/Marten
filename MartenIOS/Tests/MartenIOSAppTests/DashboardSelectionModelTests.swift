import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class DashboardSelectionModelTests: XCTestCase {
    func testSelectionModeClearsSelectionWhenDisabled() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Selection")

        let model = DashboardSelectionModel()
        model.isSelectionMode = true
        model.toggleSelection(for: item)

        XCTAssertEqual(model.selectedCount, 1)

        model.isSelectionMode = false

        XCTAssertEqual(model.selectedCount, 0)
        XCTAssertFalse(model.hasSelection)
    }

    func testDragPayloadUsesCurrentSelectionWhenItemSelectedInSelectionMode() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let first = try store.createTextItem(text: "First")
        let second = try store.createTextItem(text: "Second")

        let model = DashboardSelectionModel()
        model.isSelectionMode = true
        model.setSelection([first.objectID, second.objectID])

        let payload = model.dragPayload(for: first)
        XCTAssertEqual(payload.objectURIStrings.count, 2)
    }
}
