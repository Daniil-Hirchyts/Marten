@testable import MartenIOSApp
import XCTest

final class SourceAppIconBadgeTests: XCTestCase {
    func testKnownBundleIDMapsToExpectedSymbol() {
        let descriptor = SourceAppIconDescriptor.resolve(
            bundleID: "com.apple.MobileSMS",
            appName: "Messages"
        )

        XCTAssertEqual(descriptor.content, .symbol("message.fill"))
    }

    func testUnknownBundleUsesMonogramFallback() {
        let descriptor = SourceAppIconDescriptor.resolve(
            bundleID: "com.example.superapp",
            appName: "Super App"
        )

        XCTAssertEqual(descriptor.content, .monogram("SA"))
    }

    func testBundlePrefixMatchUsesKnownSymbol() {
        let descriptor = SourceAppIconDescriptor.resolve(
            bundleID: "com.apple.MobileSMS.ShareExtension",
            appName: "Messages Share"
        )

        XCTAssertEqual(descriptor.content, .symbol("message.fill"))
    }

    func testAppNameKeywordMatchUsesKnownSymbol() {
        let descriptor = SourceAppIconDescriptor.resolve(
            bundleID: nil,
            appName: "Telegram"
        )

        XCTAssertEqual(descriptor.content, .symbol("paperplane.fill"))
    }

    func testMissingBundleAndNameUsesGenericGlyph() {
        let descriptor = SourceAppIconDescriptor.resolve(
            bundleID: nil,
            appName: nil
        )

        XCTAssertEqual(descriptor.content, .generic)
    }

    func testHashColorIsDeterministicForSameIdentifier() {
        let first = SourceAppIconDescriptor.resolve(
            bundleID: "com.example.same",
            appName: "First Name"
        )
        let second = SourceAppIconDescriptor.resolve(
            bundleID: "com.example.same",
            appName: "Second Name"
        )

        XCTAssertEqual(first.backgroundHex, second.backgroundHex)
    }
}
