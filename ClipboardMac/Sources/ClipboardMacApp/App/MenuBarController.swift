import AppKit
import ClipboardMacServices
import Combine
import SwiftUI

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let toggleHandler: () -> Void
    private let hideOverlayHandler: (@escaping () -> Void) -> Void
    private let screenSharingManager: ScreenSharingManager
    private let pasteboardMonitor: PasteboardMonitor
    private let openNewTextItemHandler: () -> Void
    private var screenSharingMenuItem: NSMenuItem?
    private var pauseMenuItem: NSMenuItem?
    private var pauseSubmenu: NSMenu?
    private var pauseEndDate: Date?
    private var countdownTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(
        toggleHandler: @escaping () -> Void,
        hideOverlayHandler: @escaping (@escaping () -> Void) -> Void,
        screenSharingManager: ScreenSharingManager,
        pasteboardMonitor: PasteboardMonitor,
        openNewTextItemHandler: @escaping () -> Void = {}
    ) {
        self.toggleHandler = toggleHandler
        self.hideOverlayHandler = hideOverlayHandler
        self.screenSharingManager = screenSharingManager
        self.pasteboardMonitor = pasteboardMonitor
        self.openNewTextItemHandler = openNewTextItemHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.doc", accessibilityDescription: "Clipboard")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let showClipboardItem = NSMenuItem(
            title: "Show Clipboard", action: #selector(showClipboard), keyEquivalent: "v")
        showClipboardItem.target = self
        showClipboardItem.image = NSImage(
            systemSymbolName: "clipboard", accessibilityDescription: nil)
        menu.addItem(showClipboardItem)

        let newTextItem = NSMenuItem(
            title: "New Text Item", action: #selector(openNewTextItem), keyEquivalent: "n")
        newTextItem.target = self
        newTextItem.image = NSImage(
            systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        menu.addItem(newTextItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause Capture", action: nil, keyEquivalent: "")
        pauseItem.image = NSImage(
            systemSymbolName: "pause.circle", accessibilityDescription: nil)
        let submenu = NSMenu()
        for (title, seconds) in MenuBarController.pauseDurations {
            let item = NSMenuItem(
                title: title, action: #selector(pauseCapture), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let indefiniteItem = NSMenuItem(
            title: "Until Resumed", action: #selector(pauseCapture), keyEquivalent: "")
        indefiniteItem.target = self
        indefiniteItem.representedObject = 0
        submenu.addItem(indefiniteItem)
        pauseItem.submenu = submenu
        pauseMenuItem = pauseItem
        pauseSubmenu = submenu
        menu.addItem(pauseItem)

        let screenSharingItem = NSMenuItem(
            title: "Screen Sharing Mode",
            action: #selector(toggleScreenSharingMode),
            keyEquivalent: "p"
        )
        screenSharingItem.keyEquivalentModifierMask = [.command, .shift]
        screenSharingItem.target = self
        screenSharingItem.state = screenSharingManager.isScreenSharingModeActive ? .on : .off
        screenSharingItem.image = NSImage(
            systemSymbolName: "rectangle.inset.filled.on.rectangle", accessibilityDescription: nil)
        menu.addItem(screenSharingItem)
        screenSharingMenuItem = screenSharingItem

        screenSharingManager.$isScreenSharingModeActive
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive in
                self?.screenSharingMenuItem?.state = isActive ? .on : .off
            }
            .store(in: &cancellables)

        pasteboardMonitor.$isPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] isPaused in
                self?.updatePauseMenuItem(isPaused: isPaused)
            }
            .store(in: &cancellables)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func showClipboard() {
        toggleHandler()
    }

    @objc private func openNewTextItem() {
        openNewTextItemHandler()
    }

    @objc private func toggleScreenSharingMode() {
        screenSharingManager.toggle()
    }

    @objc private func openSettings() {
        hideOverlayHandler {
            // Call the AppDelegate method to open settings
            NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func pauseCapture(_ sender: NSMenuItem) {
        let seconds = sender.representedObject as? Int ?? 0
        pasteboardMonitor.pauseForDuration(seconds == 0 ? nil : TimeInterval(seconds))
        if seconds > 0 {
            pauseEndDate = Date().addingTimeInterval(TimeInterval(seconds))
            startCountdownTimer()
        }
    }

    @objc private func resumeCapture() {
        pasteboardMonitor.resume()
    }

    private func updatePauseMenuItem(isPaused: Bool) {
        if isPaused {
            pauseMenuItem?.title = "Resume Capture"
            pauseMenuItem?.action = #selector(resumeCapture)
            pauseMenuItem?.target = self
            pauseMenuItem?.submenu = nil
            pauseMenuItem?.image = NSImage(
                systemSymbolName: "play.circle", accessibilityDescription: nil)
        } else {
            stopCountdownTimer()
            pauseMenuItem?.title = "Pause Capture"
            pauseMenuItem?.action = nil
            pauseMenuItem?.target = nil
            pauseMenuItem?.submenu = pauseSubmenu
            pauseMenuItem?.image = NSImage(
                systemSymbolName: "pause.circle", accessibilityDescription: nil)
        }
    }

    // MARK: - Countdown

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            self?.tickCountdown()
        }
        if let timer = countdownTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        tickCountdown()
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        pauseEndDate = nil
    }

    private func tickCountdown() {
        guard let endDate = pauseEndDate else {
            stopCountdownTimer()
            return
        }
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            stopCountdownTimer()
            return
        }
        pauseMenuItem?.title =
            "Resume Capture (\(MenuBarController.formatDuration(remaining)))"
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private static let pauseDurations: [(String, Int)] = [
        ("5 Minutes", 300),
        ("15 Minutes", 900),
        ("30 Minutes", 1800),
        ("1 Hour", 3600),
    ]
}
