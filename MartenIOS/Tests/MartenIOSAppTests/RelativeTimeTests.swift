@testable import MartenIOSApp
import XCTest

final class RelativeTimeTests: XCTestCase {
    func testShortRelativeTimeFormatsExpectedUnits() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-10), now: now), "now")
        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-120), now: now), "2m")
        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-3_600), now: now), "1h")
        XCTAssertEqual(RelativeTime.short(from: now.addingTimeInterval(-172_800), now: now), "2d")
    }
}
