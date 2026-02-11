import XCTest
@testable import MartenCore

final class ShareCoordinatorEmailNormalizationTests: XCTestCase {
    func testNormalizedParticipantEmailAddressAcceptsPlainEmail() {
        let result = ShareCoordinator.normalizedParticipantEmailAddress("alice@example.com")
        XCTAssertEqual(result, "alice@example.com")
    }

    func testNormalizedParticipantEmailAddressNormalizesMailto() {
        let result = ShareCoordinator.normalizedParticipantEmailAddress("mailto:bob@example.com")
        XCTAssertEqual(result, "bob@example.com")
    }

    func testNormalizedParticipantEmailAddressRejectsURL() {
        let result = ShareCoordinator.normalizedParticipantEmailAddress("https://icloud.com/share/abc123")
        XCTAssertNil(result)
    }

    func testNormalizedParticipantEmailAddressRejectsInvalidEmail() {
        XCTAssertNil(ShareCoordinator.normalizedParticipantEmailAddress("invalid-email"))
        XCTAssertNil(ShareCoordinator.normalizedParticipantEmailAddress("@example.com"))
        XCTAssertNil(ShareCoordinator.normalizedParticipantEmailAddress("example.com@"))
    }
}
