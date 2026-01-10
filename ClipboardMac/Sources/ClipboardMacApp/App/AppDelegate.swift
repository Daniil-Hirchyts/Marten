import AppKit
import ClipboardCore
import ClipboardMacServices
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let persistence = PersistenceController.shared
    private lazy var clipItemStore = ClipItemStore(persistence: persistence)
    private let pasteboardMonitor = PasteboardMonitor()
    private let pasteboardExtractor = PasteboardExtractor()
    private let thumbnailGenerator = ThumbnailGenerator()
    private let hotkeyManager = HotkeyManager()
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayWindowController(persistence: persistence)

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

        hotkeyManager.registerToggleOverlayHotkey { [weak self] in
            self?.toggleOverlay()
        }

        menuBarController = MenuBarController { [weak self] in
            self?.toggleOverlay()
        }

        if ProcessInfo.processInfo.environment["PASTE_AUTOSHOW_OVERLAY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleOverlay()
            }
        }

        scheduleRetentionCleanup()
        Logger.app.info("ClipboardMac finished launching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        pasteboardMonitor.stop()
        hotkeyManager.unregister()
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

    private func toggleOverlay() {
        overlayController?.toggle()
    }

    private func scheduleRetentionCleanup() {
        runRetentionCleanup()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runRetentionCleanup()
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
}
