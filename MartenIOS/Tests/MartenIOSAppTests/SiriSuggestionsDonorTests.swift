import MartenCore
@testable import MartenIOSApp
import XCTest

@MainActor
final class SiriSuggestionsDonorTests: XCTestCase {
    func testDonateSearchAndOpenActivities() throws {
        let donorDouble = MockUserActivityDonor()
        let donor = SiriSuggestionsDonor(donor: donorDouble)

        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let item = try store.createTextItem(text: "Search me")
        let pinboard = try store.createPinboard(name: "Team", colorHex: "#123456")

        donor.donateSearch(query: "query")
        donor.donateOpenItem(item)
        donor.donateOpenPinboard(pinboard)

        let activityTypes = donorDouble.donatedActivities.map(\.activityType)
        XCTAssertTrue(activityTypes.contains(SiriSuggestionsDonor.searchActivityType))
        XCTAssertTrue(activityTypes.contains(SiriSuggestionsDonor.openItemActivityType))
        XCTAssertTrue(activityTypes.contains(SiriSuggestionsDonor.openPinboardActivityType))
    }
}
