import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import Foundation
import OSLog

protocol HotkeyPermissionManaging: AccessibilityPermissionChecking {
    func requestAccessibility()
}

extension PermissionManager: HotkeyPermissionManaging {}

@MainActor
final class HotkeyCoordinator {
    private let hotkeyManager: HotkeyManager
    private let permissionManager: any HotkeyPermissionManaging
    private let clipItemStore: ClipItemStore
    private let pasteEngine: any PasteEngineProtocol
    private let pasteSettings: any PasteSettingsProviding
    private let hideOverlayForPaste: (@escaping () -> Void) -> Void
    private let toggleOverlay: () -> Void
    private let triggerOCRCapture: () -> Void

    private var hotkeyRetryTimer: Timer?

    init(
        hotkeyManager: HotkeyManager,
        permissionManager: any HotkeyPermissionManaging,
        clipItemStore: ClipItemStore,
        pasteEngine: any PasteEngineProtocol,
        pasteSettings: any PasteSettingsProviding,
        toggleOverlay: @escaping () -> Void,
        hideOverlayForPaste: @escaping (@escaping () -> Void) -> Void,
        triggerOCRCapture: @escaping () -> Void
    ) {
        self.hotkeyManager = hotkeyManager
        self.permissionManager = permissionManager
        self.clipItemStore = clipItemStore
        self.pasteEngine = pasteEngine
        self.pasteSettings = pasteSettings
        self.toggleOverlay = toggleOverlay
        self.hideOverlayForPaste = hideOverlayForPaste
        self.triggerOCRCapture = triggerOCRCapture
    }

    func start() {
        registerHotkeys()
        requestAccessibilityForHotkeysIfNeeded()
    }

    func stop() {
        hotkeyRetryTimer?.invalidate()
        hotkeyRetryTimer = nil
        hotkeyManager.stop()
        hotkeyManager.unregisterAll()
    }

    func reload() {
        registerHotkeys()
    }

    private func registerHotkeys() {
        hotkeyManager.unregisterAll()

        if let hotkey = HotkeyPreferencesStore.effectiveHotkey(for: .showClipboard) {
            hotkeyManager.register(action: "showClipboard", hotkey: hotkey) { [weak self] _ in
                Task { @MainActor in
                    self?.toggleOverlay()
                }
            }
        }

        if let hotkey = HotkeyPreferencesStore.effectiveHotkey(for: .ocrCapture) {
            hotkeyManager.register(action: "ocrCapture", hotkey: hotkey) { [weak self] _ in
                Task { @MainActor in
                    self?.triggerOCRCapture()
                }
            }
        }

        for index in 1...9 {
            if let hotkey = HotkeyPreferencesStore.effectiveHotkey(for: .quickPaste(index)) {
                hotkeyManager.register(action: "quickPaste\(index)", hotkey: hotkey) {
                    [weak self] flags in
                    Task { @MainActor in
                        self?.quickPaste(index: index, flags: flags)
                    }
                }
            }
        }

        guard permissionManager.checkAccessibility(prompt: false) else {
            return
        }

        if !hotkeyManager.start() {
            scheduleHotkeyStartRetry()
        }
    }

    private func requestAccessibilityForHotkeysIfNeeded() {
        if permissionManager.checkAccessibility(prompt: false) {
            return
        }
        scheduleHotkeyStartRetry()
    }

    private func scheduleHotkeyStartRetry() {
        hotkeyRetryTimer?.invalidate()
        hotkeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                if self.permissionManager.checkAccessibility(prompt: false) {
                    if self.hotkeyManager.start() {
                        timer.invalidate()
                    }
                }
            }
        }

        if let timer = hotkeyRetryTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func quickPaste(index: Int, flags: NSEvent.ModifierFlags) {
        let alwaysPlainText = pasteSettings.alwaysPastePlainText
        let isPlainText = flags.contains(.shift) || alwaysPlainText

        do {
            let items = try clipItemStore.fetchRecentItems(limit: index)
            guard items.count >= index else { return }
            let item = items[index - 1]
            try? clipItemStore.markItemUsed(objectID: item.objectID)

            hideOverlayForPaste { [weak self] in
                guard let self else { return }
                self.pasteEngine.recordFrontmostApp()
                Task {
                    do {
                        try await self.pasteEngine.pasteItem(
                            item,
                            format: isPlainText ? .plainText : .preserved
                        )
                    } catch PasteEngineError.accessibilityPermissionDenied {
                        self.permissionManager.requestAccessibility()
                    } catch {
                        Logger.app.error("Quick paste failed: \(error.localizedDescription)")
                        CrashReporter.shared.recordPasteError(
                            error,
                            operation: "Quick Paste \(index)",
                            targetApp: nil
                        )
                    }
                }
            }
        } catch {
            Logger.app.error("Quick paste failed: \(error.localizedDescription)")
            CrashReporter.shared.recordPasteError(
                error,
                operation: "Quick Paste Fetch",
                targetApp: nil
            )
        }
    }
}
