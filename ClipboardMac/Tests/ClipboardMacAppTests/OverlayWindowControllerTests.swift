import AppKit
@testable import ClipboardMac
import ClipboardCore
import ClipboardMacServices
import SwiftUI
import XCTest

@MainActor
final class OverlayWindowControllerTests: XCTestCase {
    func testToggleShowsAndHidesOverlay() {
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
            rootView: AnyView(Text("Test"))
        )

        controller.toggle()
        spinRunLoop(for: 0.3)
        XCTAssertTrue(controller.isVisibleForTesting)

        controller.toggle()
        spinRunLoop(for: 0.3)
        XCTAssertFalse(controller.isVisibleForTesting)
    }

    private func spinRunLoop(for interval: TimeInterval) {
        let end = Date().addingTimeInterval(interval)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: end)
        }
    }
}
