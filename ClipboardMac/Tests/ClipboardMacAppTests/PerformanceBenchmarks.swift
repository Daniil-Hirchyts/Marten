import AppKit
import ClipboardCore
import ClipboardMacServices
import SwiftUI
import XCTest

@testable import ClipboardMac

@MainActor
final class PerformanceBenchmarks: XCTestCase {
    func testOverlayTogglePerformance() {
        _ = NSApplication.shared
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        let appleIntelligence = AppleIntelligenceTextService()
        let itemEditorWindowController = ItemEditorWindowController(
            clipItemEditor: store,
            appleIntelligence: appleIntelligence
        )
        let overlayDependencies = OverlayDependencies(
            clipItemStore: store,
            itemOperations: ItemOperationsHandler(store: store),
            pinboards: PinboardManager(store: store, persistence: persistence),
            previewCoordinator: OverlayPreviewCoordinator(itemEditorWindowController: itemEditorWindowController),
            appleIntelligence: appleIntelligence,
            soundPlayer: SoundEffectPlayer()
        )
        let controller = OverlayWindowController(
            persistence: persistence,
            pasteEngine: PasteEngine(),
            permissionManager: PermissionManager(),
            hotkeyManager: nil,
            eventBroadcaster: ClipboardEventBroadcasterImpl(),
            screenSharingManager: ScreenSharingManager(),
            overlayDependencies: overlayDependencies,
            rootView: AnyView(Text("Benchmark"))
        )
        let showDuration: TimeInterval = 0.2
        let hideDuration: TimeInterval = 0.2

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            if controller.isVisibleForTesting {
                controller.toggle()
                spinRunLoop(for: hideDuration)
            }

            startMeasuring()
            controller.toggle()
            spinRunLoop(for: showDuration)
            controller.toggle()
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
