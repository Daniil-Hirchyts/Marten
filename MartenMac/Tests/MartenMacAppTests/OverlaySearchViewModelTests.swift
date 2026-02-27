import MartenCore
import MartenMacServices
import XCTest

@testable import MartenMac

@MainActor
final class OverlaySearchViewModelTests: XCTestCase {
    func testSearchDebouncesAndEventuallyReturnsResults() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        _ = try store.createTextItem(text: "hello world")
        _ = try store.createTextItem(text: "another")

        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("SearchTests-\(UUID().uuidString)")))
        )

        let model = OverlaySearchViewModel(services: services, debounceNanoseconds: 80_000_000)
        model.searchText = "hello"

        spinRunLoop(for: 0.02)
        XCTAssertTrue(model.searchResults.isEmpty)

        spinRunLoop(for: 0.12)
        XCTAssertEqual(model.searchResults.count, 1)
        XCTAssertEqual(model.searchResults.first?.plainTextContent, "hello world")
    }

    func testApplyFiltersRespectsDateAndAppFilters() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let recent = try store.createTextItem(
            text: "recent",
            sourceApp: .init(bundleID: "com.test.recent", name: "RecentApp")
        )
        let old = try store.createTextItem(
            text: "old",
            sourceApp: .init(bundleID: "com.test.old", name: "OldApp")
        )

        try persistence.viewContext.performAndWaitThrowing {
            old.createdAt = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
            try persistence.viewContext.save()
        }

        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("SearchTests-\(UUID().uuidString)")))
        )
        let model = OverlaySearchViewModel(services: services, debounceNanoseconds: 0)
        model.dateFilter = .last7Days
        model.appFilters = ["com.test.recent"]

        let filtered = model.applyFilters(to: [recent, old])
        XCTAssertEqual(
            filtered.map { $0.objectID.uriRepresentation() },
            [recent.objectID.uriRepresentation()]
        )

        model.updateAppOptions(from: [recent, old])
        XCTAssertEqual(model.appOptions.map(\.id), ["com.test.old", "com.test.recent"])
    }

    func testUpdateAppOptionsNormalizesMartenVariants() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let canonical = try store.createTextItem(
            text: "canonical",
            sourceApp: .init(
                bundleID: SourceAppIdentity.martenBundleID,
                name: SourceAppIdentity.martenDisplayName
            )
        )
        let variant = try store.createTextItem(
            text: "variant",
            sourceApp: .init(
                bundleID: "com.hirchyts.marten.watch",
                name: SourceAppIdentity.martenDisplayName
            )
        )
        let thirdParty = try store.createTextItem(
            text: "other",
            sourceApp: .init(bundleID: "com.test.other", name: "Other")
        )

        let services = TestAppServices(
            persistence: persistence,
            clipItemStore: store,
            pasteEngine: PasteEngine(
                pasteboard: NSPasteboard(name: .init("SearchTests-\(UUID().uuidString)")))
        )
        let model = OverlaySearchViewModel(services: services, debounceNanoseconds: 0)

        model.updateAppOptions(from: [canonical, variant, thirdParty])
        XCTAssertEqual(model.appOptions.map(\.id), ["com.hirchyts.marten", "com.test.other"])

        model.appFilters = [SourceAppIdentity.martenBundleID]
        let filtered = model.applyFilters(to: [canonical, variant, thirdParty])
        let ids = Set(filtered.map(\.objectID))
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.contains(canonical.objectID))
        XCTAssertTrue(ids.contains(variant.objectID))
    }
}
