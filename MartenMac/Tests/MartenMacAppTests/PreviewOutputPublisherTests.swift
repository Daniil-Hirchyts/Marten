import XCTest

@testable import MartenMac

@MainActor
final class PreviewOutputPublisherTests: XCTestCase {
    func testPublishUpdatesBindingAndInvokesCallback() {
        var bindingValue: Int? = nil
        var callbackInvoked = false
        var callbackValue: Int?

        PreviewOutputPublisher.publish(42, binding: &bindingValue) { value in
            callbackInvoked = true
            callbackValue = value
        }

        XCTAssertEqual(bindingValue, 42)
        XCTAssertTrue(callbackInvoked)
        XCTAssertEqual(callbackValue, 42)
    }

    func testPublishPropagatesNilCleanupToBindingAndCallback() {
        var bindingValue: Int? = 7
        var callbackInvoked = false
        var callbackValue: Int? = 99

        PreviewOutputPublisher.publish(nil as Int?, binding: &bindingValue) { value in
            callbackInvoked = true
            callbackValue = value
        }

        XCTAssertNil(bindingValue)
        XCTAssertTrue(callbackInvoked)
        XCTAssertNil(callbackValue)
    }
}
