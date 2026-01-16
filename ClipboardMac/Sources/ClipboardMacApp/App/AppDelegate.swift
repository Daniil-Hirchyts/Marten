import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import Combine
import Foundation
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services: AppServiceProviding
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var retentionTimer: Timer?
    private var hotkeyRetryTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let captureQueue = DispatchQueue(label: "paste.app.capture", qos: .utility)

    private let soundPlayer = SoundEffectPlayer()
    private let linkPreviewFetcher = LinkPreviewFetcher()
    private var onboardingWindow: NSWindow?

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
        NSApp.setActivationPolicy(.regular)

        overlayController = OverlayWindowController(
            persistence: persistence,
            pasteEngine: pasteEngine,
            permissionManager: permissionManager,
            hotkeyManager: hotkeyManager,
            eventBroadcaster: eventBroadcaster,
            screenSharingManager: screenSharingManager
        )

        eventBroadcaster.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard event == .clipboardWillWrite else { return }
                self?.pasteboardMonitor.suppressNextChange()
            }
            .store(in: &cancellables)

        pasteboardMonitor.onClipboardChange = { [weak self] pasteboard in
            Task { @MainActor in
                self?.handlePasteboardChange(pasteboard)
            }
        }
        pasteboardMonitor.start()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindowIfNeeded()
        }

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if UserDefaults.standard.bool(forKey: "generateLinkPreviews") {
                    self.schedulePendingLinkPreviewFetches()
                }
                self.reloadHotkeys()
            }
            .store(in: &cancellables)

        registerHotkeys()

        menuBarController = MenuBarController(
            toggleHandler: { [weak self] in
                Task { @MainActor in
                    self?.toggleOverlay(mode: .browse)
                }
            },
            pasteStackHandler: { [weak self] in
                Task { @MainActor in
                    self?.toggleOverlay(mode: .pasteStack)
                }
            },
            screenSharingManager: screenSharingManager
        )

        if ProcessInfo.processInfo.environment["PASTE_AUTOSHOW_OVERLAY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleOverlay(mode: .browse)
            }
        }

        scheduleRetentionCleanup()
        permissionManager.startMonitoring()
        requestInputMonitoringIfNeeded()
        performStartupIntegrityCheck()
        Logger.app.info("ClipboardMac finished launching")
    }

    @MainActor
    private func performStartupIntegrityCheck() {
        Logger.integrity.info("Starting startup integrity check")

        // 1. Check if ClipItemStore is accessible
        do {
            // Perform a lightweight fetch to verify database access
            let recentItems = try clipItemStore.fetchRecentItems(limit: 1)
            Logger.integrity.info(
                "Database access verified. Found \(recentItems.count) recent items.")
        } catch {
            Logger.integrity.fault(
                "Critical: Database access failed during integrity check: \(error.localizedDescription)"
            )
        }

        // 2. Check Retention Policy validity
        let rawPolicy = UserDefaults.standard.string(forKey: "retentionPolicy")
        if let raw = rawPolicy, RetentionPolicy(rawValue: raw) == nil {
            Logger.integrity.error(
                "Invalid retention policy found in UserDefaults: \(raw). Defaulting to month.")
        } else {
            Logger.integrity.info("Retention policy verified: \(rawPolicy ?? "default")")
        }

        Logger.integrity.info("Startup integrity check completed")
    }

    @MainActor
    private func registerHotkeys() {
        hotkeyManager.unregisterAll()

        hotkeyManager.register(
            action: "toggleOverlay",
            hotkey: HotkeyPreferencesStore.effectiveHotkey(for: .toggleOverlay)
        ) { [weak self] _ in
            Task { @MainActor in
                self?.toggleOverlay(mode: .browse)
            }
        }

        hotkeyManager.register(
            action: "togglePasteStack",
            hotkey: HotkeyPreferencesStore.effectiveHotkey(for: .togglePasteStack)
        ) { [weak self] _ in
            Task { @MainActor in
                self?.toggleOverlay(mode: .pasteStack)
            }
        }

        for index in 1...9 {
            hotkeyManager.register(
                action: "quickPaste\(index)", hotkey: DefaultHotkey.quickPaste(index)
            ) { [weak self] flags in
                Task { @MainActor in
                    self?.quickPaste(index: index, flags: flags)
                }
            }
        }

        hotkeyManager.start()
    }

    @MainActor
    private func reloadHotkeys() {
        registerHotkeys()
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        pasteboardMonitor.stop()
        hotkeyManager.stop()
        hotkeyManager.unregisterAll()
        permissionManager.stopMonitoring()
        hotkeyRetryTimer?.invalidate()
        retentionTimer?.invalidate()
    }

    @MainActor
    private func handlePasteboardChange(_ pasteboard: NSPasteboard) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = SourceAppInfo(
            bundleID: frontmost?.bundleIdentifier, name: frontmost?.localizedName)

        guard let payload = pasteboardExtractor.extract(from: pasteboard) else {
            return
        }

        let clipItemStore = clipItemStore
        let thumbnailGenerator = thumbnailGenerator
        captureQueue.async {
            do {
                let item = try clipItemStore.createItem(payload: payload, sourceApp: source)
                let itemID = item.objectID
                if let thumbnailData = Self.thumbnailData(
                    from: payload, thumbnailGenerator: thumbnailGenerator)
                {
                    try? clipItemStore.updateThumbnail(objectID: itemID, data: thumbnailData)
                }

                DispatchQueue.main.async { [weak self] in
                    self?.soundPlayer.play(.capture)
                }

                if payload.needsLinkPreview, let text = payload.primaryText,
                    let url = URL(string: text)
                {
                    Self.scheduleLinkPreviewFetch(
                        itemID: itemID,
                        url: url,
                        clipItemStore: clipItemStore,
                        linkPreviewFetcher: self.linkPreviewFetcher
                    )
                }
                Logger.pasteboard.info("Captured clipboard item")
            } catch {
                Logger.pasteboard.error(
                    "Failed to capture clipboard item: \(error.localizedDescription)")
            }
        }
    }

    private static func thumbnailData(
        from payload: ClipItemPayload, thumbnailGenerator: ThumbnailGenerator
    ) -> Data? {
        let imageKinds: Set<RepresentationKind> = [.png, .jpeg, .tiff, .pdf]
        guard let imageRep = payload.representations.first(where: { imageKinds.contains($0.kind) }),
            let data = imageRep.data
        else {
            return nil
        }
        return try? thumbnailGenerator.generateThumbnail(from: data).get()
    }

    private static func scheduleLinkPreviewFetch(
        itemID: NSManagedObjectID,
        url: URL,
        clipItemStore: ClipItemStore,
        linkPreviewFetcher: LinkPreviewFetcher
    ) {
        guard UserDefaults.standard.bool(forKey: "generateLinkPreviews") else {
            return
        }

        Task.detached(priority: .utility) {
            do {
                let preview = try await linkPreviewFetcher.fetchPreview(for: url)
                try clipItemStore.updateLinkPreview(objectID: itemID, payload: preview)
            } catch LinkPreviewError.disabled {
            } catch {
                try? clipItemStore.markLinkPreviewFetchFailed(objectID: itemID, url: url)
            }
        }
    }

    @MainActor
    private func schedulePendingLinkPreviewFetches() {
        let clipItemStore = clipItemStore
        captureQueue.async {
            guard let pending = try? clipItemStore.fetchPendingLinkPreviewTargets(limit: 25) else {
                return
            }
            for target in pending {
                Self.scheduleLinkPreviewFetch(
                    itemID: target.objectID,
                    url: target.url,
                    clipItemStore: clipItemStore,
                    linkPreviewFetcher: self.linkPreviewFetcher
                )
            }
        }
    }

    private func showOnboardingWindowIfNeeded() {
        guard onboardingWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Paste"
        window.isReleasedWhenClosed = false
        window.center()

        let hosting = NSHostingController(
            rootView: OnboardingFlow(onClose: { [weak window, weak self] in
                window?.close()
                self?.onboardingWindow = nil
            })
        )
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @MainActor
    private func toggleOverlay(mode: OverlayMode) {
        pasteEngine.recordFrontmostApp()
        overlayController?.toggle(mode: mode)
    }

    @MainActor
    private func quickPaste(index: Int, flags: NSEvent.ModifierFlags) {
        let alwaysPlainText = UserDefaults.standard.bool(forKey: "alwaysPastePlainText")
        let isPlainText = flags.contains(.shift) || alwaysPlainText
        let shouldPasteToActiveApp =
            UserDefaults.standard.object(forKey: "pasteToActiveApp") as? Bool ?? true
        do {
            let items = try clipItemStore.fetchRecentItems(limit: index)
            guard items.count >= index else { return }
            let item = items[index - 1]
            try? clipItemStore.markItemUsed(objectID: item.objectID)
            overlayController?.hideForPaste { [weak self] in
                guard let self else { return }
                self.pasteEngine.recordFrontmostApp()
                Task {
                    do {
                        if shouldPasteToActiveApp {
                            try await self.pasteEngine.pasteItem(
                                item, format: isPlainText ? .plainText : .preserved)
                        } else {
                            try await self.pasteEngine.copyItemToClipboard(
                                item, format: isPlainText ? .plainText : .preserved)
                        }
                    } catch PasteEngineError.accessibilityPermissionDenied {
                        self.permissionManager.requestAccessibility()
                    } catch {
                        Logger.app.error("Quick paste failed: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            Logger.app.error("Quick paste failed: \(error.localizedDescription)")
        }
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
        }
    }

    @MainActor
    private func requestInputMonitoringIfNeeded() {
        if permissionManager.checkInputMonitoring(prompt: true) {
            return
        }

        hotkeyRetryTimer?.invalidate()
        hotkeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                if self.permissionManager.checkInputMonitoring(prompt: false) {
                    self.hotkeyManager.start()
                    timer.invalidate()
                }
            }
        }

        if let timer = hotkeyRetryTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}

extension AppDelegate: @unchecked Sendable {}
