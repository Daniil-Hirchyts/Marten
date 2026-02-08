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
    private var originalWindowSharingTypes: [ObjectIdentifier: NSWindow.SharingType] = [:]

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
                "hasCompletedOnboarding": false,
                "soundEffectsEnabled": true,
                "openAtLogin": false,
                "alwaysPastePlainText": false,
                "ignoreConfidentialContent": true,
                "ignoreTransientContent": true,
                "showDuringScreenSharing": true,
                "hideMenuBarIcon": false,
                AppSettingsKeys.showDockIconForSettingsWindow: false,
                AppSettingsKeys.hasSeededStarterContent: false,
                OCRSettingsKeys.defaultMode: OCRCaptureMode.staticSnapshot.rawValue,
                OCRSettingsKeys.preferredLanguage: "",
                OverlayLayoutSettings.Keys.overlayScreenEdge: OverlayLayoutSettings.defaultEdge.rawValue,
                OverlayLayoutSettings.Keys.overlayWidth: OverlayLayoutSettings.defaultVerticalSize,
                "retentionPolicy": "month",
                PinboardSecuritySettings.unlockDurationSecondsKey: PinboardSecuritySettings.defaultUnlockDurationSeconds,
            ]
        )

        applyDockIconPolicy()
        configureScreenSharingCaptureProtection()

        guard let permissionManager = services.permissionManager as? PermissionManager else {
            preconditionFailure("AppServiceProviding.permissionManager must be a PermissionManager")
        }
        permissionManagerImpl = permissionManager

        let firstLaunchContentSeeder = FirstLaunchContentSeeder(clipItemStore: clipItemStore)
        firstLaunchContentSeeder.seedIfNeeded()

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
            soundPlayer: services.soundPlayer,
            screenSharingManager: screenSharingManager,
            pasteboardMonitor: pasteboardMonitor
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

        let onboardingCoordinator = OnboardingCoordinator(
            permissionManager: permissionManager,
            onWindowClosed: { [weak self] in
                self?.applyDockIconPolicy()
            }
        )
        self.onboardingCoordinator = onboardingCoordinator
        onboardingCoordinator.startIfNeeded()

        let integrityCheckService = IntegrityCheckService(clipItemStore: clipItemStore)
        self.integrityCheckService = integrityCheckService
        integrityCheckService.runStartupCheck()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyDockIconPolicy()
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

        if let syncCoordinator = services.syncCoordinator {
            Task {
                do {
                    try await syncCoordinator.startSync()
                } catch {
                    Logger.app.error("Failed to start iCloud sync: \(error.localizedDescription)")
                }
            }
        }

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
        services.syncCoordinator?.stopSync()

        permissionManagerImpl?.stopMonitoring()
        retentionTimer?.invalidate()
    }

    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let syncCoordinator = services.syncCoordinator else { return }
        await syncCoordinator.handlePushNotification()
    }

    public func openSettings() {
        if shouldShowDockIconForSettingsWindow {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

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

    private func configureScreenSharingCaptureProtection() {
        applyScreenSharingCaptureProtection(isEnabled: screenSharingManager.isScreenSharingModeActive)

        screenSharingManager.$isScreenSharingModeActive
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.applyScreenSharingCaptureProtection(isEnabled: isEnabled)
            }
            .store(in: &cancellables)

        let visibilityNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didExposeNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]

        Publishers.MergeMany(
            visibilityNotifications.map { NotificationCenter.default.publisher(for: $0) }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard
                let self,
                let window = notification.object as? NSWindow
            else { return }
            self.applyScreenSharingCaptureProtection(
                to: window,
                isEnabled: self.screenSharingManager.isScreenSharingModeActive
            )
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.originalWindowSharingTypes.removeValue(forKey: ObjectIdentifier(window))
                if window.identifier?.rawValue == "settings" {
                    self?.applyDockIconPolicy()
                }
            }
            .store(in: &cancellables)
    }

    private var shouldShowDockIconForSettingsWindow: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKeys.showDockIconForSettingsWindow)
    }

    private var isOnboardingWindowVisible: Bool {
        NSApp.windows.contains { window in
            window.identifier?.rawValue == "onboarding" && window.isVisible
        }
    }

    private var isSettingsWindowVisible: Bool {
        NSApp.windows.contains { window in
            window.identifier?.rawValue == "settings" && window.isVisible
        }
    }

    private func applyDockIconPolicy() {
        let shouldShowDockIcon = isOnboardingWindowVisible
            || (shouldShowDockIconForSettingsWindow && isSettingsWindowVisible)
        NSApp.setActivationPolicy(shouldShowDockIcon ? .regular : .accessory)
    }

    private func applyScreenSharingCaptureProtection(isEnabled: Bool) {
        for window in NSApp.windows {
            applyScreenSharingCaptureProtection(to: window, isEnabled: isEnabled)
        }

        if !isEnabled {
            originalWindowSharingTypes.removeAll()
        }
    }

    private func applyScreenSharingCaptureProtection(to window: NSWindow, isEnabled: Bool) {
        let windowID = ObjectIdentifier(window)

        if isEnabled {
            if originalWindowSharingTypes[windowID] == nil {
                originalWindowSharingTypes[windowID] = window.sharingType
            }
            if window.sharingType != .none {
                window.sharingType = .none
            }
            return
        }

        guard let originalSharingType = originalWindowSharingTypes[windowID] else { return }
        if window.sharingType != originalSharingType {
            window.sharingType = originalSharingType
        }
    }

    private var hasPushNotificationEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = "com.apple.developer.aps-environment" as CFString
        return SecTaskCopyValueForEntitlement(task, entitlement, nil) != nil
    }

    func openNewTextItem() {
        itemEditorWindowController?.showNewTextItem(
            onSave: { [weak self] text in
                Task { @MainActor [weak self] in
                    await self?.saveNewTextItem(text)
                }
            },
            onClose: {
            }
        )
    }

    func saveNewTextItem(_ text: String) async {
        let sourceApp = SourceAppInfo(
            bundleID: Bundle.main.bundleIdentifier,
            name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        )

        var savedToHistory = false
        var savedToClipboard = false

        do {
            _ = try clipItemStore.createTextItem(
                text: text,
                sourceApp: sourceApp,
                isUserCreated: true
            )
            savedToHistory = true
        } catch {
            Logger.app.error("Failed to save text to history: \(error.localizedDescription)")
        }

        do {
            try await pasteEngine.copyPlainTextToClipboard(text)
            savedToClipboard = true
        } catch {
            Logger.app.error("Failed to save text to clipboard: \(error.localizedDescription)")
        }

        if savedToHistory, savedToClipboard {
            Logger.app.info("New text item saved to history and clipboard")
        } else if savedToHistory {
            Logger.app.info("New text item saved to history only")
        } else if savedToClipboard {
            Logger.app.info("New text item saved to clipboard only")
        } else {
            Logger.app.error("Failed to save new text item to history and clipboard")
        }
    }
}
