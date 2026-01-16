import ClipboardCore
import ClipboardMacServices

@MainActor
protocol AppServiceProviding: AnyObject {
    var persistence: PersistenceController { get }
    var clipItemStore: ClipItemStore { get }

    var pasteboardMonitor: PasteboardMonitor { get }
    var pasteboardExtractor: PasteboardExtractor { get }
    var thumbnailGenerator: ThumbnailGenerator { get }

    var hotkeyManager: HotkeyManager { get }
    var permissionManager: PermissionManager { get }
    var activeAppTracker: ActiveAppTracker { get }
    var eventBroadcaster: any ClipboardEventBroadcaster { get }
    var pasteEngine: PasteEngine { get }
}

@MainActor
final class AppServiceContainer: AppServiceProviding {
    let persistence: PersistenceController
    let pasteboardMonitor: PasteboardMonitor
    let pasteboardExtractor: PasteboardExtractor
    let thumbnailGenerator: ThumbnailGenerator
    let hotkeyManager: HotkeyManager
    let permissionManager: PermissionManager
    let activeAppTracker: ActiveAppTracker
    let eventBroadcaster: any ClipboardEventBroadcaster

    lazy var clipItemStore: ClipItemStore = ClipItemStore(persistence: persistence)
    lazy var pasteEngine: PasteEngine = PasteEngine(
        activeAppTracker: activeAppTracker,
        permissionManager: permissionManager,
        eventBroadcaster: eventBroadcaster
    )

    init(
        persistence: PersistenceController = .shared,
        pasteboardMonitor: PasteboardMonitor = PasteboardMonitor(),
        pasteboardExtractor: PasteboardExtractor = PasteboardExtractor(),
        thumbnailGenerator: ThumbnailGenerator = ThumbnailGenerator(),
        hotkeyManager: HotkeyManager = HotkeyManager(),
        permissionManager: PermissionManager = PermissionManager(),
        activeAppTracker: ActiveAppTracker = ActiveAppTracker(),
        eventBroadcaster: any ClipboardEventBroadcaster = ClipboardEventBroadcasterImpl()
    ) {
        self.persistence = persistence
        self.pasteboardMonitor = pasteboardMonitor
        self.pasteboardExtractor = pasteboardExtractor
        self.thumbnailGenerator = thumbnailGenerator
        self.hotkeyManager = hotkeyManager
        self.permissionManager = permissionManager
        self.activeAppTracker = activeAppTracker
        self.eventBroadcaster = eventBroadcaster
    }
}
