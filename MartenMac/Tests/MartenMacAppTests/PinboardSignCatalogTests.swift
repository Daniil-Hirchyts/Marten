import XCTest

@testable import MartenMac

final class PinboardSignCatalogTests: XCTestCase {
    func testSignResolverDetectsSymbolAndEmoji() {
        XCTAssertEqual(PinboardSignResolver.resolve("star.fill"), .symbol("star.fill"))
        XCTAssertEqual(PinboardSignResolver.resolve("🎉"), .text("🎉"))
        XCTAssertNil(PinboardSignResolver.resolve("   "))
    }

    func testPreferredTabUsesCurrentSelectionType() {
        XCTAssertEqual(PinboardSignCatalog.preferredTab(for: "star.fill"), .icon)
        XCTAssertEqual(PinboardSignCatalog.preferredTab(for: "😀"), .emoji)
        XCTAssertEqual(PinboardSignCatalog.preferredTab(for: nil), .emoji)
    }

    func testCatalogFilteringMatchesLabelsAndTokens() {
        let iconResults = PinboardSignCatalog.filteredOptions(for: .icon, query: "folder")
        XCTAssertTrue(iconResults.contains(where: { $0.token == "folder.fill" }))

        let emojiResults = PinboardSignCatalog.filteredOptions(for: .emoji, query: "celebrate")
        XCTAssertTrue(emojiResults.contains(where: { $0.token == "🥳" }))
    }
}
