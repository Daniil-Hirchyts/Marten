import AppKit
import SwiftUI
import XCTest

@testable import ClipboardMac

@MainActor
final class PerformanceBenchmarks: XCTestCase {
    func testOverlayTogglePerformance() {
        _ = NSApplication.shared
        let controller = OverlayWindowController(rootView: AnyView(Text("Benchmark")))
        let showDuration: TimeInterval = 0.2
        let hideDuration: TimeInterval = 0.2

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            if controller.isVisibleForTesting {
                controller.toggle(mode: .browse)
                spinRunLoop(for: hideDuration)
            }

            startMeasuring()
            controller.toggle(mode: .browse)
            spinRunLoop(for: showDuration)
            controller.toggle(mode: .browse)
            spinRunLoop(for: hideDuration)
            stopMeasuring()
        }
    }

    private func spinRunLoop(for interval: TimeInterval) {
        let end = Date().addingTimeInterval(interval)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: end)
        }
    }
}
