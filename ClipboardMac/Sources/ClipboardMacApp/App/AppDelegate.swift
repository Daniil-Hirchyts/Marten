import AppKit
import ClipboardCore
import ClipboardMacServices
import Foundation
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let persistence = PersistenceController.shared
    private lazy var clipItemStore = ClipItemStore(persistence: persistence)
    private let pasteboardMonitor = PasteboardMonitor()
    private let pasteboardExtractor = PasteboardExtractor()
    private let thumbnailGenerator = ThumbnailGenerator()
    private let hotkeyManager = HotkeyManager()
    private let permissionManager = PermissionManager()
    private let activeAppTracker = ActiveAppTracker()
    private lazy var pasteEngine = PasteEngine(
        activeAppTracker: activeAppTracker,
        permissionManager: permissionManager
    )
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var retentionTimer: Timer?
    private var hotkeyRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        overlayController = OverlayWindowController(
            persistence: persistence,
            pasteEngine: pasteEngine,
            permissionManager: permissionManager,
            hotkeyManager: hotkeyManager
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardWillWrite),
            name: .clipboardWillWrite,
            object: nil
        )

        pasteboardMonitor.onClipboardChange = { [weak self] pasteboard in
            self?.handlePasteboardChange(pasteboard)
        }
        pasteboardMonitor.start()

        hotkeyManager.register(action: "toggleOverlay", hotkey: DefaultHotkey.activatePaste) { [weak self] _ in
            self?.toggleOverlay(mode: .browse)
        }
        hotkeyManager.register(action: "togglePasteStack", hotkey: DefaultHotkey.activatePasteStack) { [weak self] _ in
            self?.toggleOverlay(mode: .pasteStack)
        }
        for index in 1...9 {
            hotkeyManager.register(action: "quickPaste\(index)", hotkey: DefaultHotkey.quickPaste(index)) { [weak self] flags in
                self?.quickPaste(index: index, flags: flags)
            }
        }
        hotkeyManager.start()

        menuBarController = MenuBarController(
            toggleHandler: { [weak self] in
                self?.toggleOverlay(mode: .browse)
            },
            pasteStackHandler: { [weak self] in
                self?.toggleOverlay(mode: .pasteStack)
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

    func applicationWillTerminate(_ notification: Notification) {
        pasteboardMonitor.stop()
        hotkeyManager.stop()
        hotkeyManager.unregisterAll()
        permissionManager.stopMonitoring()
        hotkeyRetryTimer?.invalidate()
        retentionTimer?.invalidate()
    }

    private func handlePasteboardChange(_ pasteboard: NSPasteboard) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = SourceAppInfo(bundleID: frontmost?.bundleIdentifier, name: frontmost?.localizedName)

        guard let payload = pasteboardExtractor.extract(from: pasteboard) else {
            return
        }

        do {
            let item = try clipItemStore.createItem(payload: payload, sourceApp: source)
            if let thumbnailData = thumbnailData(from: payload) {
                try? clipItemStore.updateThumbnail(objectID: item.objectID, data: thumbnailData)
            }
            Logger.pasteboard.info("Captured clipboard item")
        } catch {
            Logger.pasteboard.error("Failed to capture clipboard item: \(error.localizedDescription)")
        }
    }

    @objc private func handleClipboardWillWrite() {
        pasteboardMonitor.suppressNextChange()
    }

    private func thumbnailData(from payload: ClipItemPayload) -> Data? {
        let imageKinds: Set<RepresentationKind> = [.png, .jpeg, .tiff, .pdf]
        guard let imageRep = payload.representations.first(where: { imageKinds.contains($0.kind) }),
              let data = imageRep.data else {
            return nil
        }
        return thumbnailGenerator.generateThumbnail(from: data)
    }

    private func toggleOverlay(mode: OverlayMode) {
        pasteEngine.recordFrontmostApp()
        overlayController?.toggle(mode: mode)
    }

    private func quickPaste(index: Int, flags: NSEvent.ModifierFlags) {
        let isPlainText = flags.contains(.shift)
        do {
            let items = try clipItemStore.fetchRecentItems(limit: index)
            guard items.count >= index else { return }
            let item = items[index - 1]
            try? clipItemStore.markItemUsed(objectID: item.objectID)
            pasteEngine.recordFrontmostApp()
            Task {
                do {
                    try await pasteEngine.pasteItem(item, format: isPlainText ? .plainText : .preserved)
                } catch PasteEngineError.accessibilityPermissionDenied {
                    permissionManager.requestAccessibility()
                } catch {
                    Logger.app.error("Quick paste failed: \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.app.error("Quick paste failed: \(error.localizedDescription)")
        }
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
            let deleted = try clipItemStore.cleanupExpiredItems(policy: .month)
            if deleted > 0 {
                Logger.retention.info("Retention cleanup removed \(deleted) items")
            }
        } catch {
            Logger.retention.error("Retention cleanup failed: \(error.localizedDescription)")
        }
    }

    private func requestInputMonitoringIfNeeded() {
        if permissionManager.checkInputMonitoring(prompt: true) {
            return
        }

        hotkeyRetryTimer?.invalidate()
        hotkeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
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
