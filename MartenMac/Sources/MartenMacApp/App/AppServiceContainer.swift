import MartenCore
import MartenMacServices
import Foundation

@MainActor
public protocol CaptureServicesProviding: AnyObject {
    var persistence: PersistenceController { get }
    var clipItemStore: ClipItemStore { get }
    var pasteboardMonitor: PasteboardMonitor { get }
    var pasteboardExtractor: PasteboardExtractor { get }
    var thumbnailGenerator: ThumbnailGenerator { get }
    var eventBroadcaster: any MartenEventBroadcaster { get }
}

@MainActor
public protocol PasteServicesProviding: AnyObject {
    var pasteEngine: any PasteEngineProtocol { get }
    var activeAppTracker: ActiveAppTracker { get }
    var permissionManager: any AccessibilityPermissionChecking { get }
    var eventBroadcaster: any MartenEventBroadcaster { get }
}

@MainActor
public protocol OverlayServicesProviding: AnyObject {
    var persistence: PersistenceController { get }
    var clipItemStore: ClipItemStore { get }
    var hotkeyManager: HotkeyManager { get }
    var permissionManager: any AccessibilityPermissionChecking { get }
    var pasteEngine: any PasteEngineProtocol { get }
    var screenSharingManager: ScreenSharingManager { get }
    var eventBroadcaster: any MartenEventBroadcaster { get }
    var soundPlayer: SoundEffectPlayer { get }
}

@MainActor
public protocol SyncServicesProviding: AnyObject {
    var syncCoordinator: SyncCoordinator? { get }
}

@MainActor
public protocol OCRServicesProviding: AnyObject {
    var screenImageCapturer: any ScreenImageCapturing { get }
    var textRecognizer: any TextRecognizing { get }
    var ocrSettings: any OCRSettingsProviding { get }
    var selectionImageCropper: SelectionImageCropper { get }
}

@MainActor
public protocol AppServiceProviding: CaptureServicesProviding, PasteServicesProviding,
    OverlayServicesProviding,
    OCRServicesProviding,
    SyncServicesProviding
{}

@MainActor
final class AppServiceContainer: AppServiceProviding {
    let persistence: PersistenceController
    let pasteboardMonitor: PasteboardMonitor
    let pasteboardExtractor: PasteboardExtractor
    let thumbnailGenerator: ThumbnailGenerator
    let hotkeyManager: HotkeyManager
    let permissionManagerImpl: PermissionManager
    var permissionManager: any AccessibilityPermissionChecking { permissionManagerImpl }
    let activeAppTracker: ActiveAppTracker
    let eventBroadcaster: any MartenEventBroadcaster
    let soundPlayer: SoundEffectPlayer
    let screenImageCapturer: any ScreenImageCapturing
    let textRecognizer: any TextRecognizing
    let ocrSettings: any OCRSettingsProviding
    let selectionImageCropper: SelectionImageCropper

    let syncCoordinator: SyncCoordinator?

    lazy var screenSharingManager = ScreenSharingManager(
        settings: UserDefaultsScreenSharingSettingsProvider()
    )
    lazy var clipItemStore: ClipItemStore = ClipItemStore(persistence: persistence)
    lazy var pasteEngine: any PasteEngineProtocol = PasteEngine(
        activeAppTracker: activeAppTracker,
        permissionManager: permissionManager,
        eventBroadcaster: eventBroadcaster
    )

    init(
        persistence: PersistenceController = .shared,
        pasteboardMonitor: PasteboardMonitor? = nil,
        pasteboardExtractor: PasteboardExtractor = PasteboardExtractor(
            settings: UserDefaultsCaptureSettingsProvider()
        ),
        thumbnailGenerator: ThumbnailGenerator = ThumbnailGenerator(),
        hotkeyManager: HotkeyManager = HotkeyManager(),
        permissionManager: PermissionManager = PermissionManager(),
        activeAppTracker: ActiveAppTracker = ActiveAppTracker(),
        eventBroadcaster: any MartenEventBroadcaster = MartenEventBroadcasterImpl(),
        soundPlayer: SoundEffectPlayer = SoundEffectPlayer(),
        screenImageCapturer: any ScreenImageCapturing = SystemScreenImageCapturer(),
        textRecognizer: any TextRecognizing = VisionTextRecognizer(),
        ocrSettings: any OCRSettingsProviding = UserDefaultsOCRSettingsProvider(),
        selectionImageCropper: SelectionImageCropper = SelectionImageCropper(),
        syncConfigurationProvider: any SyncConfigurationProviding =
            DefaultSyncConfigurationProvider()
    ) {
        self.persistence = persistence
        self.pasteboardMonitor = pasteboardMonitor ?? PasteboardMonitor(activeAppTracker: activeAppTracker)
        self.pasteboardExtractor = pasteboardExtractor
        self.thumbnailGenerator = thumbnailGenerator
        self.hotkeyManager = hotkeyManager
        self.permissionManagerImpl = permissionManager
        self.activeAppTracker = activeAppTracker
        self.eventBroadcaster = eventBroadcaster
        self.soundPlayer = soundPlayer
        self.screenImageCapturer = screenImageCapturer
        self.textRecognizer = textRecognizer
        self.ocrSettings = ocrSettings
        self.selectionImageCropper = selectionImageCropper
        let cloudKitConfiguration = CloudKitConfiguration.default
        if syncConfigurationProvider.canUseCloudKit(
            containerIdentifier: cloudKitConfiguration.containerIdentifier
        ) {
            self.syncCoordinator = SyncCoordinator.create(
                cloudKitConfiguration: cloudKitConfiguration,
                persistenceController: persistence,
                syncEnabledProvider: { [syncConfigurationProvider] in
                    syncConfigurationProvider.isSyncEnabled()
                }
            )
        } else {
            self.syncCoordinator = nil
        }
    }
}
