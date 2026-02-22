@testable import MartenIOSApp
import XCTest

final class SourceAppIconDescriptorTests: XCTestCase {

    // MARK: - Exact bundle ID lookups

    func testSafariExactBundleID() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "com.apple.mobilesafari", appName: nil)
        XCTAssertEqual(descriptor.content, .symbol("safari.fill"))
        XCTAssertEqual(descriptor.backgroundHex, "#0A84FF")
    }

    func testMailExactBundleID() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "com.apple.mobilemail", appName: nil)
        XCTAssertEqual(descriptor.content, .symbol("envelope.fill"))
        XCTAssertEqual(descriptor.backgroundHex, "#007AFF")
    }

    func testMessagesExactBundleID() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "com.apple.MobileSMS", appName: nil)
        XCTAssertEqual(descriptor.content, .symbol("message.fill"))
    }

    func testOutlookExactBundleID() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "com.microsoft.office.outlook", appName: nil)
        XCTAssertEqual(descriptor.content, .symbol("envelope.badge.fill"))
        XCTAssertEqual(descriptor.backgroundHex, "#0078D4")
    }

    // MARK: - Prefix matching

    func testMessagesPrefixMatch() {
        let descriptor = SourceAppIconDescriptor.resolve(
            bundleID: "com.apple.MobileSMS.ShareExtension",
            appName: nil
        )
        XCTAssertEqual(descriptor.content, .symbol("message.fill"))
    }

    func testChromePrefixMatch() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "com.google.chrome.beta", appName: nil)
        XCTAssertEqual(descriptor.content, .symbol("globe"))
    }

    func testMartenPrefixMatch() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "com.hirchyts.marten.dev", appName: nil)
        XCTAssertEqual(descriptor.content, .symbol("sparkles"))
        XCTAssertEqual(descriptor.backgroundHex, "#FF2E00")
    }

    // MARK: - Name keyword matching

    func testTelegramNameMatch() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: nil, appName: "Telegram")
        XCTAssertEqual(descriptor.content, .symbol("paperplane.fill"))
    }

    func testSlackNameMatch() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: nil, appName: "Slack")
        XCTAssertEqual(descriptor.content, .symbol("bubble.left.and.bubble.right.fill"))
    }

    func testMartenNameMatch() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: nil, appName: "Marten")
        XCTAssertEqual(descriptor.content, .symbol("sparkles"))
    }

    func testNameMatchIsCaseInsensitive() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: nil, appName: "TELEGRAM")
        XCTAssertEqual(descriptor.content, .symbol("paperplane.fill"))
    }

    func testXAppNameExactMatchOnly() {
        // "x" keyword only matches when the name is exactly "x"
        let exactX = SourceAppIconDescriptor.resolve(bundleID: nil, appName: "X")
        XCTAssertEqual(exactX.content, .symbol("at"))

        // "exampleapp" contains "x" but should NOT match the "x" keyword
        let containsX = SourceAppIconDescriptor.resolve(bundleID: nil, appName: "Exxxtra")
        XCTAssertNotEqual(containsX.content, .symbol("at"))
    }

    // MARK: - stableColorHex determinism

    func testStableColorHexIsDeterministicForSameIdentifier() {
        let first = SourceAppIconDescriptor.stableColorHex(forIdentifier: "com.example.app")
        let second = SourceAppIconDescriptor.stableColorHex(forIdentifier: "com.example.app")
        XCTAssertEqual(first, second)
    }

    func testStableColorHexDiffersForDifferentIdentifiers() {
        let a = SourceAppIconDescriptor.stableColorHex(forIdentifier: "com.foo.bar")
        let b = SourceAppIconDescriptor.stableColorHex(forIdentifier: "com.baz.qux")
        XCTAssertNotEqual(a, b)
    }

    func testStableColorHexIsValidHexFormat() {
        let hex = SourceAppIconDescriptor.stableColorHex(forIdentifier: "any.identifier")
        XCTAssertTrue(hex.hasPrefix("#"), "Expected hex to start with #")
        XCTAssertEqual(hex.count, 7, "Expected 7-char hex color (#RRGGBB)")
    }

    // MARK: - Generic fallback

    func testGenericFallbackForUnknownBundleIDAndNilName() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: nil, appName: nil)
        XCTAssertEqual(descriptor.content, .generic)
    }

    func testGenericFallbackForTotallyUnknownBundleWithNoName() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "io.unknown.xyz", appName: nil)
        // Should produce a monogram from the bundle suffix "xyz"
        if case .monogram(let m) = descriptor.content {
            XCTAssertFalse(m.isEmpty)
        } else {
            XCTFail("Expected monogram for unknown bundle ID with extractable suffix")
        }
    }

    func testGenericFallbackWhenBothEmpty() {
        let descriptor = SourceAppIconDescriptor.resolve(bundleID: "", appName: "")
        XCTAssertEqual(descriptor.content, .generic)
    }

    // MARK: - KnownAppSymbolMap direct tests

    func testKnownAppSymbolMapExactLookup() {
        let entry = KnownAppSymbolMap.entry(for: "com.apple.mobilesafari", appName: nil)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.symbol, "safari.fill")
    }

    func testKnownAppSymbolMapPrefixLookup() {
        let entry = KnownAppSymbolMap.entry(for: "com.apple.mobilesms.shareextension", appName: nil)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.symbol, "message.fill")
    }

    func testKnownAppSymbolMapNameKeywordLookup() {
        let entry = KnownAppSymbolMap.entry(for: nil, appName: "slack")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.symbol, "bubble.left.and.bubble.right.fill")
    }

    func testKnownAppSymbolMapReturnsNilForUnknown() {
        let entry = KnownAppSymbolMap.entry(for: "io.totally.unknown", appName: "BogusTool")
        XCTAssertNil(entry)
    }
}
