import ClipboardCore
import ClipboardMacServices
import Foundation
import Security

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
    var screenSharingManager: ScreenSharingManager { get }
    var syncCoordinator: SyncCoordinator? { get }
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

    let syncCoordinator: SyncCoordinator?

    lazy var screenSharingManager = ScreenSharingManager()
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
        let cloudKitConfiguration = CloudKitConfiguration.default
        if Self.canUseCloudKit(containerIdentifier: cloudKitConfiguration.containerIdentifier) {
            self.syncCoordinator = SyncCoordinator.create(
                cloudKitConfiguration: cloudKitConfiguration,
                persistenceController: persistence,
                syncEnabledProvider: {
                    UserDefaults.standard.bool(forKey: "com.paste.syncEnabled")
                }
            )
        } else {
            self.syncCoordinator = nil
        }
    }

    private static func canUseCloudKit(containerIdentifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let servicesKey = "com.apple.developer.icloud-services" as CFString
        let containersKey = "com.apple.developer.icloud-container-identifiers" as CFString
        let servicesValue = SecTaskCopyValueForEntitlement(task, servicesKey, nil)
        let containersValue = SecTaskCopyValueForEntitlement(task, containersKey, nil)

        let services = servicesValue as? [String]
            ?? (servicesValue as? String).map { [$0] }
            ?? []
        let containers = containersValue as? [String]
            ?? (containersValue as? String).map { [$0] }
            ?? []

        return services.contains("CloudKit") && containers.contains(containerIdentifier)
    }
}
