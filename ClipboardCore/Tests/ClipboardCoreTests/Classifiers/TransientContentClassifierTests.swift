import Foundation
import XCTest
@testable import ClipboardCore

final class TransientContentClassifierTests: XCTestCase {
    private let classifier = TransientContentClassifier()

    func testPromisedFileURLIsTransient() {
        XCTAssertTrue(classifier.isTransient(types: ["com.apple.pasteboard.promised-file-url"], dataSize: 100))
    }

    func testSmallContentIsTransient() {
        XCTAssertTrue(classifier.isTransient(types: ["public.utf8-plain-text"], dataSize: 9))
    }

    func testDynamicUTIIsTransient() {
        XCTAssertTrue(classifier.isTransient(types: ["dyn.ah62d4rv4ge80y"], dataSize: 100))
    }

    func testNormalContentIsNotTransient() {
        XCTAssertFalse(classifier.isTransient(types: ["public.utf8-plain-text"], dataSize: 100))
    }
}

