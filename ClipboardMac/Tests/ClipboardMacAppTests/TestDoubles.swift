import ClipboardCore
import ClipboardMacServices
import Foundation
import XCTest

@testable import ClipboardMac

final class TestPasteEngine: PasteEngineProtocol {
    enum Action: Equatable {
        case recordFrontmostApp
        case pasteItem(objectID: URL, format: PasteFormat)
        case pasteStack(sessionID: URL, format: PasteFormat)
        case copyItem(objectID: URL, format: PasteFormat)
        case copyStack(sessionID: URL)
        case pastePlainText(text: String)
        case copyPlainText(text: String)
    }

    private(set) var actions: [Action] = []
    var pasteItemError: Error?
    var pasteStackError: Error?
    var copyItemError: Error?
    var copyStackError: Error?
    var pastePlainTextError: Error?
    var copyPlainTextError: Error?
    var pasteStackResult: PasteStackResult = PasteStackResult(successCount: 0, skippedEntries: [])

    func recordFrontmostApp() {
        actions.append(.recordFrontmostApp)
    }

    func pasteItem(_ item: ClipItem, format: PasteFormat) async throws {
        actions.append(.pasteItem(objectID: item.objectID.uriRepresentation(), format: format))
        if let pasteItemError {
            throw pasteItemError
        }
    }

    func pasteStack(_ session: StackSession, format: PasteFormat) async throws -> PasteStackResult {
        actions.append(.pasteStack(sessionID: session.objectID.uriRepresentation(), format: format))
        if let pasteStackError {
            throw pasteStackError
        }
        return pasteStackResult
    }

    func copyItemToClipboard(_ item: ClipItem, format: PasteFormat) async throws {
        actions.append(.copyItem(objectID: item.objectID.uriRepresentation(), format: format))
        if let copyItemError {
            throw copyItemError
        }
    }

    func copyStackToClipboard(_ session: StackSession) async throws {
        actions.append(.copyStack(sessionID: session.objectID.uriRepresentation()))
        if let copyStackError {
            throw copyStackError
        }
    }

    func pastePlainText(_ text: String) async throws {
        actions.append(.pastePlainText(text: text))
        if let pastePlainTextError {
            throw pastePlainTextError
        }
    }

    func copyPlainTextToClipboard(_ text: String) async throws {
        actions.append(.copyPlainText(text: text))
        if let copyPlainTextError {
            throw copyPlainTextError
        }
    }
}

func spinRunLoop(for interval: TimeInterval) {
    let end = Date().addingTimeInterval(interval)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: end)
    }
}

@MainActor
final class TestAppServices: AppServiceProviding {
    let persistence: PersistenceController
    let clipItemStore: ClipItemStore

    let pasteboardMonitor: PasteboardMonitor
    let pasteboardExtractor: PasteboardExtractor
    let thumbnailGenerator: ThumbnailGenerator

    let hotkeyManager: HotkeyManager
    let permissionManager: any AccessibilityPermissionChecking
    let activeAppTracker: ActiveAppTracker
    let eventBroadcaster: any ClipboardEventBroadcaster
    let pasteEngine: any PasteEngineProtocol
    let screenSharingManager: ScreenSharingManager
    let syncCoordinator: SyncCoordinator?

    init(
        persistence: PersistenceController,
        clipItemStore: ClipItemStore,
        pasteEngine: any PasteEngineProtocol,
        permissionManager: any AccessibilityPermissionChecking = PermissionManager(),
        activeAppTracker: ActiveAppTracker = ActiveAppTracker(),
        eventBroadcaster: any ClipboardEventBroadcaster = ClipboardEventBroadcasterImpl()
    ) {
        self.persistence = persistence
        self.clipItemStore = clipItemStore
        self.pasteboardMonitor = PasteboardMonitor()
        self.pasteboardExtractor = PasteboardExtractor()
        self.thumbnailGenerator = ThumbnailGenerator()
        self.hotkeyManager = HotkeyManager()
        self.permissionManager = permissionManager
        self.activeAppTracker = activeAppTracker
        self.eventBroadcaster = eventBroadcaster
        self.pasteEngine = pasteEngine
        self.screenSharingManager = ScreenSharingManager()
        self.syncCoordinator = nil
    }
}
