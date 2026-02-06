import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import Combine
import Foundation
import OSLog
import Security

@MainActor
public final class AppCoordinator: SettingsOpening {
    private let services: any AppServiceProviding

    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var itemEditorWindowController: ItemEditorWindowController?
    private var retentionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let captureQueue = DispatchQueue(label: "paste.app.capture", qos: .utility)
    private let linkPreviewFetcher = LinkPreviewFetcher()

    private var permissionManagerImpl: PermissionManager?

    private var onboardingCoordinator: OnboardingCoordinator?
    private var captureCoordinator: CaptureCoordinator?
    private var hotkeyCoordinator: HotkeyCoordinator?
    private var ocrCaptureCoordinator: OCRCaptureCoordinator?
    private var integrityCheckService: IntegrityCheckService?

    private var persistence: PersistenceController { services.persistence }
    private var clipItemStore: ClipItemStore { services.clipItemStore }
    private var pasteboardMonitor: PasteboardMonitor { services.pasteboardMonitor }
    private var pasteboardExtractor: PasteboardExtractor { services.pasteboardExtractor }
    private var thumbnailGenerator: ThumbnailGenerator { services.thumbnailGenerator }
    private var hotkeyManager: HotkeyManager { services.hotkeyManager }
    private var pasteEngine: any PasteEngineProtocol { services.pasteEngine }
    private var screenSharingManager: ScreenSharingManager { services.screenSharingManager }
    private var eventBroadcaster: any ClipboardEventBroadcaster { services.eventBroadcaster }

    public init(services: any AppServiceProviding) {
        self.services = services
    }

    public func start() {
        CrashReporter.shared.setupGlobalExceptionHandler()
        CrashReporter.shared.recordLifecycleEvent(.appLaunched)

        UserDefaults.standard.register(
            defaults: [
                "hasCompletedOnboarding": true,
                "soundEffectsEnabled": true,
                "openAtLogin": false,
                "alwaysPastePlainText": false,
                "ignoreConfidentialContent": true,
                "ignoreTransientContent": true,
                "showDuringScreenSharing": true,
                "hideMenuBarIcon": false,
                OCRSettingsKeys.defaultMode: OCRCaptureMode.staticSnapshot.rawValue,
                OCRSettingsKeys.preferredLanguage: "",
                OverlayLayoutSettings.Keys.overlayScreenEdge: OverlayLayoutSettings.defaultEdge.rawValue,
                OverlayLayoutSettings.Keys.overlayWidth: OverlayLayoutSettings.defaultVerticalSize,
                "retentionPolicy": "month",
                PinboardSecuritySettings.unlockDurationSecondsKey: PinboardSecuritySettings.defaultUnlockDurationSeconds,
            ]
        )

        NSApp.setActivationPolicy(.accessory)

        guard let permissionManager = services.permissionManager as? PermissionManager else {
            preconditionFailure("AppServiceProviding.permissionManager must be a PermissionManager")
        }
        permissionManagerImpl = permissionManager

        let appleIntelligence: any AppleIntelligenceTextServicing = AppleIntelligenceTextService()
        let itemEditorWindowController = ItemEditorWindowController(
            clipItemEditor: clipItemStore,
            appleIntelligence: appleIntelligence
        )
        self.itemEditorWindowController = itemEditorWindowController

        let previewCoordinator = OverlayPreviewCoordinator(
            itemEditorWindowController: itemEditorWindowController
        )
        let overlayDependencies = OverlayDependencies(
            clipItemStore: clipItemStore,
            itemOperations: ItemOperationsHandler(store: clipItemStore, soundPlayer: services.soundPlayer),
            pinboards: PinboardManager(store: clipItemStore, persistence: persistence),
            previewCoordinator: previewCoordinator,
            appleIntelligence: appleIntelligence,
            soundPlayer: services.soundPlayer
        )

        overlayController = OverlayWindowController(
            persistence: persistence,
            pasteEngine: pasteEngine,
            permissionManager: permissionManager,
            hotkeyManager: hotkeyManager,
            eventBroadcaster: eventBroadcaster,
            screenSharingManager: screenSharingManager,
            overlayDependencies: overlayDependencies
        )

        let captureCoordinator = CaptureCoordinator(
            pasteboardMonitor: pasteboardMonitor,
            pasteboardExtractor: pasteboardExtractor,
            clipItemStore: clipItemStore,
            thumbnailGenerator: thumbnailGenerator,
            eventBroadcaster: eventBroadcaster,
            captureQueue: captureQueue,
            soundPlayer: services.soundPlayer,
            linkPreviewFetcher: linkPreviewFetcher,
            linkPreviewSettings: UserDefaultsLinkPreviewSettingsProvider()
        )
        self.captureCoordinator = captureCoordinator
        captureCoordinator.start()

        let ocrCaptureCoordinator = OCRCaptureCoordinator(
            permissionChecker: permissionManager,
            textRecognizer: services.textRecognizer,
            screenImageCapturer: services.screenImageCapturer,
            selectionImageCropper: services.selectionImageCropper,
            pasteEngine: pasteEngine,
            historyStore: clipItemStore,
            resultIndicator: OCRCaptureResultIndicatorController(),
            ocrSettings: services.ocrSettings,
            soundPlayer: services.soundPlayer
        )
        self.ocrCaptureCoordinator = ocrCaptureCoordinator

        let hotkeyCoordinator = HotkeyCoordinator(
            hotkeyManager: hotkeyManager,
            permissionManager: permissionManager,
            clipItemStore: clipItemStore,
            pasteEngine: pasteEngine,
            pasteSettings: UserDefaultsPasteSettingsProvider(),
            toggleOverlay: { [weak self] in
                Task { @MainActor in
                    self?.toggleOverlay()
                }
            },
            hideOverlayForPaste: { [weak self] completion in
                Task { @MainActor in
                    self?.overlayController?.hideForPaste(completion: completion)
                }
            },
            triggerOCRCapture: { [weak self] in
                Task { @MainActor in
                    self?.startOCRCapture()
                }
            }
        )
        self.hotkeyCoordinator = hotkeyCoordinator
        hotkeyCoordinator.start()

        let onboardingCoordinator = OnboardingCoordinator()
        self.onboardingCoordinator = onboardingCoordinator
        onboardingCoordinator.startIfNeeded()

        let integrityCheckService = IntegrityCheckService(clipItemStore: clipItemStore)
        self.integrityCheckService = integrityCheckService
        integrityCheckService.runStartupCheck()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if UserDefaults.standard.bool(forKey: "generateLinkPreviews") {
                    self.captureCoordinator?.schedulePendingLinkPreviewFetchesIfEnabled()
                }
                self.hotkeyCoordinator?.reload()
            }
            .store(in: &cancellables)

        menuBarController = MenuBarController(
            toggleHandler: { [weak self] in
                Task { @MainActor in
                    self?.toggleOverlay()
                }
            },
            hideOverlayHandler: { [weak self] completion in
                Task { @MainActor in
                    guard let self, let overlayController = self.overlayController else {
                        completion()
                        return
                    }
                    overlayController.hideForPaste(completion: completion)
                }
            },
            settingsOpener: self,
            screenSharingManager: screenSharingManager,
            pasteboardMonitor: pasteboardMonitor,
            openNewTextItemHandler: { [weak self] in
                Task { @MainActor in
                    self?.openNewTextItem()
                }
            },
            captureOCRTextHandler: { [weak self] in
                Task { @MainActor in
                    self?.startOCRCapture()
                }
            }
        )

        scheduleRetentionCleanup()
        permissionManager.startMonitoring()

        let hasSync = services.syncCoordinator != nil
        if hasSync, hasPushNotificationEntitlement {
            NSApp.registerForRemoteNotifications()
        }

        Logger.app.info("ClipboardMac finished launching")
    }

    public func stop() {
        CrashReporter.shared.recordLifecycleEvent(.appTerminating)

        captureCoordinator?.stop()
        hotkeyCoordinator?.stop()
        ocrCaptureCoordinator?.stop()

        permissionManagerImpl?.stopMonitoring()
        retentionTimer?.invalidate()
    }

    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let syncCoordinator = services.syncCoordinator else { return }
        await syncCoordinator.handlePushNotification()
    }

    public func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        if #available(macOS 14.0, *) {
            // Synthesise Cmd+, to trigger SwiftUI's openWindow via the menu command.
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: ",",
                charactersIgnoringModifiers: ",",
                isARepeat: false,
                keyCode: 43
            )
            if let event {
                NSApp.sendEvent(event)
            }

            // openWindow creates the window asynchronously; bring it to front
            // on the next run-loop tick once SwiftUI has finished creating it.
            DispatchQueue.main.async {
                if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                    w.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    public func startOCRCapture(modeOverride: OCRCaptureMode? = nil) {
        ocrCaptureCoordinator?.startCapture(modeOverride: modeOverride)
    }

    private func toggleOverlay() {
        pasteEngine.recordFrontmostApp()
        overlayController?.toggle()
    }

    private func scheduleRetentionCleanup() {
        runRetentionCleanup()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runRetentionCleanup()
            }
        }
        if let timer = retentionTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func runRetentionCleanup() {
        do {
            let raw = UserDefaults.standard.string(forKey: "retentionPolicy") ?? RetentionPolicy.month.rawValue
            let policy = RetentionPolicy(rawValue: raw) ?? .month
            let deleted = try clipItemStore.cleanupExpiredItems(policy: policy)
            if deleted > 0 {
                Logger.retention.info("Retention cleanup removed \(deleted) items")
            }
        } catch {
            Logger.retention.error("Retention cleanup failed: \(error.localizedDescription)")
            CrashReporter.shared.recordDatabaseError(
                error,
                operation: "Retention Cleanup",
                entityName: "ClipItem"
            )
        }
    }

    private var hasPushNotificationEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = "com.apple.developer.aps-environment" as CFString
        return SecTaskCopyValueForEntitlement(task, entitlement, nil) != nil
    }

    private func openNewTextItem() {
        itemEditorWindowController?.showNewTextItem(
            onSave: { [weak self] text in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.pasteEngine.copyPlainTextToClipboard(text)
                        Logger.app.info("New text item saved to clipboard")
                    } catch {
                        Logger.app.error("Failed to save text to clipboard: \(error.localizedDescription)")
                    }
                }
            },
            onClose: {
            }
        )
    }
}
