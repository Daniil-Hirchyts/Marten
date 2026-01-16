import AppKit
import ClipboardCore
import ClipboardMacServices
import Combine
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services: AppServiceProviding
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var retentionTimer: Timer?
    private var hotkeyRetryTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let captureQueue = DispatchQueue(label: "paste.app.capture", qos: .utility)

    @MainActor private var persistence: PersistenceController { services.persistence }
    @MainActor private var clipItemStore: ClipItemStore { services.clipItemStore }
    @MainActor private var pasteboardMonitor: PasteboardMonitor { services.pasteboardMonitor }
    @MainActor private var pasteboardExtractor: PasteboardExtractor { services.pasteboardExtractor }
    @MainActor private var thumbnailGenerator: ThumbnailGenerator { services.thumbnailGenerator }
    @MainActor private var hotkeyManager: HotkeyManager { services.hotkeyManager }
    @MainActor private var permissionManager: PermissionManager { services.permissionManager }
    @MainActor private var pasteEngine: PasteEngine { services.pasteEngine }
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
            eventBroadcaster: eventBroadcaster
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

        hotkeyManager.register(action: "toggleOverlay", hotkey: DefaultHotkey.activatePaste) {
            [weak self] _ in
            Task { @MainActor in
                self?.toggleOverlay(mode: .browse)
            }
        }
        hotkeyManager.register(action: "togglePasteStack", hotkey: DefaultHotkey.activatePasteStack)
        { [weak self] _ in
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
            }
        )

        if ProcessInfo.processInfo.environment["PASTE_AUTOSHOW_OVERLAY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleOverlay(mode: .browse)
            }
        }

        scheduleRetentionCleanup()
        permissionManager.startMonitoring()
        requestInputMonitoringIfNeeded()
        Logger.app.info("ClipboardMac finished launching")
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
                if let thumbnailData = Self.thumbnailData(
                    from: payload, thumbnailGenerator: thumbnailGenerator)
                {
                    try? clipItemStore.updateThumbnail(objectID: item.objectID, data: thumbnailData)
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

    @MainActor
    private func toggleOverlay(mode: OverlayMode) {
        pasteEngine.recordFrontmostApp()
        overlayController?.toggle(mode: mode)
    }

    @MainActor
    private func quickPaste(index: Int, flags: NSEvent.ModifierFlags) {
        let isPlainText = flags.contains(.shift)
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
                        try await self.pasteEngine.pasteItem(
                            item, format: isPlainText ? .plainText : .preserved)
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
            let deleted = try clipItemStore.cleanupExpiredItems(policy: .month)
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
