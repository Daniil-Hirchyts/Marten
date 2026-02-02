import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import Combine
import Foundation
import OSLog
import Security
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services: AppServiceProviding
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var retentionTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let captureQueue = DispatchQueue(label: "paste.app.capture", qos: .utility)

    private let soundPlayer = SoundEffectPlayer()
    private let linkPreviewFetcher = LinkPreviewFetcher()

    private var onboardingCoordinator: OnboardingCoordinator?
    private var captureCoordinator: CaptureCoordinator?
    private var hotkeyCoordinator: HotkeyCoordinator?
    private var integrityCheckService: IntegrityCheckService?

    @MainActor private var persistence: PersistenceController { services.persistence }
    @MainActor private var clipItemStore: ClipItemStore { services.clipItemStore }
    @MainActor private var pasteboardMonitor: PasteboardMonitor { services.pasteboardMonitor }
    @MainActor private var pasteboardExtractor: PasteboardExtractor { services.pasteboardExtractor }
    @MainActor private var thumbnailGenerator: ThumbnailGenerator { services.thumbnailGenerator }
    @MainActor private var hotkeyManager: HotkeyManager { services.hotkeyManager }
    @MainActor private var permissionManager: PermissionManager { services.permissionManager }
    @MainActor private var pasteEngine: PasteEngine { services.pasteEngine }
    @MainActor private var screenSharingManager: ScreenSharingManager {
        services.screenSharingManager
    }
    @MainActor private var eventBroadcaster: any ClipboardEventBroadcaster {
        services.eventBroadcaster
    }

    @MainActor
    override init() {
        self.services = AppServiceContainer()
        super.init()
    }

    @MainActor
    init(services: AppServiceProviding) {
        self.services = services
        super.init()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup crash reporting first
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
                "retentionPolicy": "month",
                PinboardSecuritySettings.unlockDurationSecondsKey:
                    PinboardSecuritySettings.defaultUnlockDurationSeconds,
            ]
        )

        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController(
            persistence: persistence,
            pasteEngine: pasteEngine,
            permissionManager: permissionManager,
            hotkeyManager: hotkeyManager,
            eventBroadcaster: eventBroadcaster,
            screenSharingManager: screenSharingManager,
            clipItemStore: clipItemStore
        )

        let captureCoordinator = CaptureCoordinator(
            pasteboardMonitor: pasteboardMonitor,
            pasteboardExtractor: pasteboardExtractor,
            clipItemStore: clipItemStore,
            thumbnailGenerator: thumbnailGenerator,
            eventBroadcaster: eventBroadcaster,
            captureQueue: captureQueue,
            soundPlayer: soundPlayer,
            linkPreviewFetcher: linkPreviewFetcher
        )
        self.captureCoordinator = captureCoordinator
        captureCoordinator.start()

        let hotkeyCoordinator = HotkeyCoordinator(
            hotkeyManager: hotkeyManager,
            permissionManager: permissionManager,
            clipItemStore: clipItemStore,
            pasteEngine: pasteEngine,
            toggleOverlay: { [weak self] in
                self?.toggleOverlay()
            },
            hideOverlayForPaste: { [weak self] completion in
                self?.overlayController?.hideForPaste(completion: completion)
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
            screenSharingManager: screenSharingManager
        )

        if ProcessInfo.processInfo.environment["PASTE_AUTOSHOW_OVERLAY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleOverlay()
            }
        }

        scheduleRetentionCleanup()
        permissionManager.startMonitoring()

        let hasSync = services.syncCoordinator != nil
        if hasSync, hasPushNotificationEntitlement {
            NSApp.registerForRemoteNotifications()
        } else if hasSync {
            Logger.app.debug(
                "Skipping remote notifications registration (missing Push entitlement)")
        }

        Logger.app.info("ClipboardMac finished launching")
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Logger.app.info("Registered for remote notifications")
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.app.error(
            "Failed to register for remote notifications: \(error.localizedDescription)"
        )
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        guard let syncCoordinator = services.syncCoordinator else { return }

        Task {
            await syncCoordinator.handlePushNotification()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.shared.recordLifecycleEvent(.appTerminating)

        captureCoordinator?.stop()
        hotkeyCoordinator?.stop()

        permissionManager.stopMonitoring()
        retentionTimer?.invalidate()
    }

    @MainActor
    private func toggleOverlay() {
        pasteEngine.recordFrontmostApp()
        overlayController?.toggle()
    }

    @MainActor
    private func scheduleRetentionCleanup() {
        runRetentionCleanup()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.runRetentionCleanup()
            }
        }
        if let timer = retentionTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @MainActor
    private func runRetentionCleanup() {
        do {
            let raw =
                UserDefaults.standard.string(forKey: "retentionPolicy")
                ?? RetentionPolicy.month.rawValue
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

    @MainActor
    @objc func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Find existing settings window
        if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }
        ) {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        // On macOS 14+, the SwiftUI command will handle opening the window
        // We trigger it by sending the keyboard shortcut
        if #available(macOS 14.0, *) {
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
            if let event = event {
                NSApp.sendEvent(event)
            }
        }
    }

}

extension AppDelegate: @unchecked Sendable {}
