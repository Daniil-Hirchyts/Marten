import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class DashboardSearchModelTests: XCTestCase {
    func testLatestSearchResultWinsWhenEarlierRequestFinishesLater() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let firstItem = try store.createTextItem(text: "First Result")
        let secondItem = try store.createTextItem(text: "Second Result")

        let queryService = MockQueryService(
            responsesByQuery: [
                "first": [firstItem],
                "second": [secondItem],
            ]
        )
        let model = DashboardSearchModel(
            queryService: queryService,
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.query = "first"
        model.query = "second"

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(model.results.count, 1)
        XCTAssertEqual(model.results.first?.objectID, secondItem.objectID)
    }

    func testFilterOnlySearchIsActiveAndIncludesFilterInRequest() async throws {
        let queryService = MockQueryService(responsesByQuery: [:])
        let model = DashboardSearchModel(
            queryService: queryService,
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.toggleType(.code)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(model.isSearchActive)
        let lastRequest = await queryService.lastCapturedRequest
        XCTAssertTrue(lastRequest?.itemTypes.contains(.code) == true)
    }

    func testUpdateOptionsBucketsLocalAndUnknownSourceDevices() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let localItem = try store.createTextItem(text: "Local")
        let unknownItem = try store.createTextItem(text: "Unknown")

        try mutate(localItem) { item in
            item.lastModifiedBy = "local"
        }
        try mutate(unknownItem) { item in
            item.lastModifiedBy = "unknown"
        }

        let model = DashboardSearchModel(
            queryService: MockQueryService(responsesByQuery: [:]),
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.updateOptions(from: [localItem, unknownItem])

        let thisDevice = model.deviceOptions.first { $0.value == .thisDevice }
        let unknown = model.deviceOptions.first { $0.value == .unknown }
        XCTAssertEqual(thisDevice?.count, 1)
        XCTAssertEqual(unknown?.count, 1)
    }

    func testUpdateOptionsGroupsByBundleID() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item1 = try store.createTextItem(text: "First")
        let item2 = try store.createTextItem(text: "Second")

        try mutate(item1) { item in
            item.sourceAppBundleID = "com.example.app"
            item.sourceAppName = "Example"
        }
        try mutate(item2) { item in
            item.sourceAppBundleID = "com.example.app"
            item.sourceAppName = "Example"
        }

        let model = DashboardSearchModel(
            queryService: MockQueryService(responsesByQuery: [:]),
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.updateOptions(from: [item1, item2])

        let appOption = model.appOptions.first { $0.bundleID == "com.example.app" }
        XCTAssertNotNil(appOption)
        XCTAssertEqual(appOption?.count, 2)
        XCTAssertEqual(appOption?.name, "Example")
    }

    func testSuggestedAppsLimitedToTopFive() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)

        var items: [ClipItem] = []
        for i in 0..<8 {
            let item = try store.createTextItem(text: "Item \(i)")
            try mutate(item) { item in
                item.sourceAppBundleID = "com.app.\(i)"
                item.sourceAppName = "App \(i)"
            }
            items.append(item)
        }

        let model = DashboardSearchModel(
            queryService: MockQueryService(responsesByQuery: [:]),
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.updateOptions(from: items)

        XCTAssertEqual(model.suggestedApps.count, 5)
    }

    func testDeviceClassificationNamedDevice() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Named")

        try mutate(item) { item in
            item.lastModifiedBy = "MacBook Pro"
        }

        let model = DashboardSearchModel(
            queryService: MockQueryService(responsesByQuery: [:]),
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.updateOptions(from: [item])

        let named = model.deviceOptions.first { $0.value == .named("MacBook Pro") }
        XCTAssertNotNil(named)
        XCTAssertEqual(named?.count, 1)
        XCTAssertEqual(named?.title, "MacBook Pro")
    }

    func testClearAllFiltersResetsAllSelections() async throws {
        let queryService = MockQueryService(responsesByQuery: [:])
        let model = DashboardSearchModel(
            queryService: queryService,
            voiceService: VoiceDictationService(client: MockVoiceRecognitionClient()),
            siriDonor: SiriSuggestionsDonor(donor: MockUserActivityDonor()),
            debounceNanoseconds: 0
        )

        model.dateFilter = .today
        model.selectedTypes = [.code, .image]
        model.selectedSourceApps = ["com.example.app"]
        model.selectedSourceDevices = [.thisDevice]

        XCTAssertTrue(model.hasActiveFilters)

        model.clearAllFilters()

        XCTAssertEqual(model.dateFilter, .any)
        XCTAssertTrue(model.selectedTypes.isEmpty)
        XCTAssertTrue(model.selectedSourceApps.isEmpty)
        XCTAssertTrue(model.selectedSourceDevices.isEmpty)
        XCTAssertFalse(model.hasActiveFilters)
    }

    private func mutate(_ item: ClipItem, _ changes: (ClipItem) -> Void) throws {
        guard let context = item.managedObjectContext else { return }
        try context.performAndWaitThrowing {
            changes(item)
            try context.save()
        }
    }
}

private actor MockQueryService: ClipItemQuerying {
    private let responsesByQuery: [String: [ClipItem]]
    private(set) var lastCapturedRequest: ClipItemSearchRequest?

    init(responsesByQuery: [String: [ClipItem]]) {
        self.responsesByQuery = responsesByQuery
    }

    func search(request: ClipItemSearchRequest) async throws -> [ClipItem] {
        lastCapturedRequest = request

        // Purposefully delay "first" to verify stale result suppression.
        if request.query == "first" {
            try await Task.sleep(nanoseconds: 250_000_000)
        } else {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        return responsesByQuery[request.query] ?? []
    }
}
