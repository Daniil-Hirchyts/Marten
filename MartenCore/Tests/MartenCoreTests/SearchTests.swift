import XCTest
@testable import MartenCore

final class SearchTests: XCTestCase {
    func testSearchItemsReturnsMatches() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        _ = try store.createTextItem(text: "Alpha Bravo")
        _ = try store.createTextItem(text: "Charlie Delta")
        _ = try store.createTextItem(text: "Echo Foxtrot")

        let matches = try store.searchItems(query: "bravo")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.primaryText, "Alpha Bravo")
    }

    func testSearchRequestHonorsQueryPinboardAndDate() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let pinboardA = try store.createPinboard(name: "Team A", colorHex: "#FF0000")
        let pinboardB = try store.createPinboard(name: "Team B", colorHex: "#00FF00")

        let todayMatch = try store.createTextItem(text: "Project Atlas match")
        let oldMatch = try store.createTextItem(text: "Project Atlas match old")

        try store.moveItem(objectID: todayMatch.objectID, toPinboard: pinboardA.objectID)
        try store.moveItem(objectID: oldMatch.objectID, toPinboard: pinboardB.objectID)

        let oldDate = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date()
        try mutate(oldMatch) { item in
            item.createdAt = oldDate
            item.modifiedAt = oldDate
        }

        let request = ClipItemSearchRequest(
            query: "atlas",
            pinboardID: pinboardA.id,
            dateFilter: .today,
            limit: 20
        )

        let results = try store.searchItems(request: request)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.objectID, todayMatch.objectID)
    }

    func testSearchRequestYesterdayFilterUsesDayBoundary() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let yesterdayItem = try store.createTextItem(text: "From yesterday")
        let todayItem = try store.createTextItem(text: "From today")

        let startOfToday = Calendar.current.startOfDay(for: Date())
        let yesterdayDate = Calendar.current.date(byAdding: .hour, value: -12, to: startOfToday) ?? Date()

        try mutate(yesterdayItem) { item in
            item.createdAt = yesterdayDate
            item.modifiedAt = yesterdayDate
        }

        let request = ClipItemSearchRequest(
            query: "",
            dateFilter: .yesterday,
            limit: 20
        )
        let results = try store.searchItems(request: request)

        XCTAssertTrue(results.contains(where: { $0.objectID == yesterdayItem.objectID }))
        XCTAssertFalse(results.contains(where: { $0.objectID == todayItem.objectID }))
    }

    func testSearchRequestTypeAndSourceAppFilters() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let codeItem = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("let value = 42")],
                primaryText: "let value = 42",
                itemType: .code
            ),
            sourceApp: SourceAppInfo(bundleID: "com.apple.xcode", name: "Xcode"),
            isUserCreated: true
        )

        _ = try store.createItem(
            payload: ClipItemPayload(
                representations: [.plainText("Plain note")],
                primaryText: "Plain note",
                itemType: .text
            ),
            sourceApp: SourceAppInfo(bundleID: "com.apple.notes", name: "Notes"),
            isUserCreated: true
        )

        let request = ClipItemSearchRequest(
            query: "",
            itemTypes: [.code],
            sourceApps: ["com.apple.xcode"],
            limit: 20
        )

        let results = try store.searchItems(request: request)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.objectID, codeItem.objectID)
    }

    func testSearchRequestSourceDeviceFilters() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let thisDeviceItem = try store.createTextItem(text: "Local Marker")
        let thisDeviceFallbackItem = try store.createTextItem(text: "Local Fallback")
        let unknownItem = try store.createTextItem(text: "Unknown")
        let remoteItem = try store.createTextItem(text: "Remote")

        try mutate(thisDeviceItem) { item in
            item.lastModifiedBy = "local device"
        }
        try mutate(unknownItem) { item in
            item.lastModifiedBy = "Unknown"
        }
        try mutate(remoteItem) { item in
            item.lastModifiedBy = "Daniil iPhone"
        }

        let thisDeviceResults = try store.searchItems(
            request: ClipItemSearchRequest(
                sourceDevices: [.thisDevice],
                limit: 20
            )
        )
        XCTAssertTrue(thisDeviceResults.contains(where: { $0.objectID == thisDeviceItem.objectID }))
        XCTAssertTrue(
            thisDeviceResults.contains(where: { $0.objectID == thisDeviceFallbackItem.objectID })
        )
        XCTAssertFalse(thisDeviceResults.contains(where: { $0.objectID == unknownItem.objectID }))

        let unknownResults = try store.searchItems(
            request: ClipItemSearchRequest(
                sourceDevices: [.unknown],
                limit: 20
            )
        )
        XCTAssertTrue(unknownResults.contains(where: { $0.objectID == unknownItem.objectID }))
        XCTAssertFalse(unknownResults.contains(where: { $0.objectID == remoteItem.objectID }))

        let namedResults = try store.searchItems(
            request: ClipItemSearchRequest(
                sourceDevices: [.named("Daniil iPhone")],
                limit: 20
            )
        )
        XCTAssertEqual(namedResults.count, 1)
        XCTAssertEqual(namedResults.first?.objectID, remoteItem.objectID)
    }

    func testSearchRequestAllowsFilterOnlyWithoutQuery() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let notesItem = try store.createTextItem(
            text: "Meeting summary",
            sourceApp: SourceAppInfo(bundleID: "com.apple.notes", name: "Notes"),
            isUserCreated: true
        )
        _ = try store.createTextItem(
            text: "Another app note",
            sourceApp: SourceAppInfo(bundleID: "com.apple.reminders", name: "Reminders"),
            isUserCreated: true
        )

        let results = try store.searchItems(
            request: ClipItemSearchRequest(
                sourceApps: ["com.apple.notes"],
                limit: 20
            )
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.objectID, notesItem.objectID)
    }

    func testSearchRequestMartenFilterMatchesCanonicalAndLegacyVariants() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        let canonical = try store.createTextItem(
            text: "Canonical Marten",
            sourceApp: SourceAppInfo(
                bundleID: SourceAppIdentity.martenBundleID,
                name: SourceAppIdentity.martenDisplayName
            ),
            isUserCreated: true
        )
        let watchVariant = try store.createTextItem(
            text: "Watch Variant",
            sourceApp: SourceAppInfo(
                bundleID: "com.hirchyts.marten.watch",
                name: SourceAppIdentity.martenDisplayName
            ),
            isUserCreated: true
        )
        let nameOnly = try store.createTextItem(
            text: "Name Only",
            sourceApp: SourceAppInfo(
                bundleID: nil,
                name: SourceAppIdentity.martenDisplayName
            ),
            isUserCreated: true
        )
        _ = try store.createTextItem(
            text: "Other App",
            sourceApp: SourceAppInfo(bundleID: "com.apple.notes", name: "Notes"),
            isUserCreated: true
        )

        let results = try store.searchItems(
            request: ClipItemSearchRequest(
                sourceApps: [SourceAppIdentity.martenBundleID],
                limit: 20
            )
        )

        let resultIDs = Set(results.map(\.objectID))
        XCTAssertTrue(resultIDs.contains(canonical.objectID))
        XCTAssertTrue(resultIDs.contains(watchVariant.objectID))
        XCTAssertTrue(resultIDs.contains(nameOnly.objectID))
        XCTAssertEqual(results.count, 3)
    }

    private func mutate(_ item: ClipItem, _ changes: (ClipItem) -> Void) throws {
        guard let context = item.managedObjectContext else { return }
        try context.performAndWaitThrowing {
            changes(item)
            try context.save()
        }
    }
}
