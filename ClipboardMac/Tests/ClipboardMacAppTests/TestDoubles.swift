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
    }

    private(set) var actions: [Action] = []
    var pasteItemError: Error?
    var pasteStackError: Error?
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
    let permissionManager: PermissionManager
    let activeAppTracker: ActiveAppTracker
    let eventBroadcaster: any ClipboardEventBroadcaster
    let pasteEngine: PasteEngine

    init(
        persistence: PersistenceController,
        clipItemStore: ClipItemStore,
        pasteEngine: PasteEngine,
        permissionManager: PermissionManager = PermissionManager(),
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
    }
}
