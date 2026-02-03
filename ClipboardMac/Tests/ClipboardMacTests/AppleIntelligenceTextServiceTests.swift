import FoundationModels
import XCTest

@testable import ClipboardMacServices

final class AppleIntelligenceTextServiceTests: XCTestCase {
    func testAvailabilityMapsDeviceNotEligible() {
        let availability = AppleIntelligenceTextService.availability(
            for: .unavailable(.deviceNotEligible),
            localeSupported: true
        )
        XCTAssertEqual(availability, .unavailable(.deviceNotEligible))
    }

    func testAvailabilityMapsAppleIntelligenceNotEnabled() {
        let availability = AppleIntelligenceTextService.availability(
            for: .unavailable(.appleIntelligenceNotEnabled),
            localeSupported: true
        )
        XCTAssertEqual(availability, .unavailable(.appleIntelligenceNotEnabled))
    }

    func testAvailabilityMapsModelNotReady() {
        let availability = AppleIntelligenceTextService.availability(
            for: .unavailable(.modelNotReady),
            localeSupported: true
        )
        XCTAssertEqual(availability, .unavailable(.modelNotReady))
    }

    func testAvailabilityMapsUnsupportedLocaleWhenModelIsAvailable() {
        let availability = AppleIntelligenceTextService.availability(
            for: .available,
            localeSupported: false
        )
        XCTAssertEqual(availability, .unavailable(.unsupportedLocale))
    }

    func testTransformRejectsEmptyInputWithoutCallingTransformer() async {
        let counter = Counter()
        let service = AppleIntelligenceTextService(
            availabilityResolver: { _ in .available },
            transformer: { _, _, _ in
                await counter.increment()
                return "unused"
            }
        )

        do {
            _ = try await service.transform("   ", action: .summarize, locale: .current)
            XCTFail("Expected empty input error")
        } catch let error as AppleIntelligenceTextTransformationError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let callCount = await counter.value
        XCTAssertEqual(callCount, 0)
    }

    func testTransformMapsUnknownErrorToGenerationFailed() async {
        let service = AppleIntelligenceTextService(
            availabilityResolver: { _ in .available },
            transformer: { _, _, _ in
                throw DummyError.failed
            }
        )

        do {
            _ = try await service.transform("Hello", action: .rewrite, locale: .current)
            XCTFail("Expected generation failed error")
        } catch let error as AppleIntelligenceTextTransformationError {
            XCTAssertEqual(error, .generationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstructionCompositionForAllActions() {
        let summarize = AppleIntelligenceTextService.instructions(for: .summarize)
        XCTAssertTrue(summarize.localizedCaseInsensitiveContains("one to two sentences"))
        XCTAssertTrue(summarize.localizedCaseInsensitiveContains("return only the rewritten text"))

        let proofread = AppleIntelligenceTextService.instructions(for: .proofread)
        XCTAssertTrue(proofread.localizedCaseInsensitiveContains("grammar"))
        XCTAssertTrue(proofread.localizedCaseInsensitiveContains("spelling"))

        let rewrite = AppleIntelligenceTextService.instructions(for: .rewrite)
        XCTAssertTrue(rewrite.localizedCaseInsensitiveContains("clarity"))
        XCTAssertTrue(rewrite.localizedCaseInsensitiveContains("flow"))

        let shorten = AppleIntelligenceTextService.instructions(for: .shorten)
        XCTAssertTrue(shorten.localizedCaseInsensitiveContains("more concise"))
        XCTAssertTrue(shorten.localizedCaseInsensitiveContains("preserving key meaning"))
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private enum DummyError: Error {
    case failed
}
