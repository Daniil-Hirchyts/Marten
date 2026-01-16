import AppKit
import ClipboardCore
import ClipboardMacServices
import Combine
import OSLog
import SwiftUI

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let toggleHandler: () -> Void
    private let pasteStackHandler: () -> Void
    private let screenSharingManager: ScreenSharingManager
    private var screenSharingMenuItem: NSMenuItem?
    private let store = ClipItemStore()
    private var newItemPanel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(
        toggleHandler: @escaping () -> Void,
        pasteStackHandler: @escaping () -> Void,
        screenSharingManager: ScreenSharingManager
    ) {
        self.toggleHandler = toggleHandler
        self.pasteStackHandler = pasteStackHandler
        self.screenSharingManager = screenSharingManager
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

        let toggleItem = NSMenuItem(
            title: "Toggle Overlay", action: #selector(toggleOverlay), keyEquivalent: "v")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let stackItem = NSMenuItem(
            title: "Paste Stack", action: #selector(openPasteStack), keyEquivalent: "c")
        stackItem.target = self
        menu.addItem(stackItem)

        let newItem = NSMenuItem(
            title: "New Text Item", action: #selector(showNewTextItem), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let screenSharingItem = NSMenuItem(
            title: "Screen Sharing Mode",
            action: #selector(toggleScreenSharingMode),
            keyEquivalent: "p"
        )
        screenSharingItem.keyEquivalentModifierMask = [.command, .shift]
        screenSharingItem.target = self
        screenSharingItem.state = screenSharingManager.isScreenSharingModeActive ? .on : .off
        menu.addItem(screenSharingItem)
        screenSharingMenuItem = screenSharingItem

        screenSharingManager.$isScreenSharingModeActive
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive in
                self?.screenSharingMenuItem?.state = isActive ? .on : .off
            }
            .store(in: &cancellables)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func toggleOverlay() {
        toggleHandler()
    }

    @objc private func openPasteStack() {
        pasteStackHandler()
    }

    @objc private func toggleScreenSharingMode() {
        screenSharingManager.toggle()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showNewTextItem() {
        let panel = ensureNewItemPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureNewItemPanel() -> NSPanel {
        if let newItemPanel {
            return newItemPanel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.title = "New Text Item"
        panel.center()

        let rootView = NewTextItemSheet { [weak self] text in
            self?.createNewTextItem(text)
            self?.closeNewItemPanel()
        } onCancel: { [weak self] in
            self?.closeNewItemPanel()
        }

        panel.contentView = NSHostingView(rootView: rootView)
        newItemPanel = panel
        return panel
    }

    private func closeNewItemPanel() {
        newItemPanel?.orderOut(nil)
    }

    private func createNewTextItem(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try store.createTextItem(text: trimmed, isUserCreated: true)
        } catch {
            Logger.app.error("Failed to create new text item: \(error.localizedDescription)")
        }
    }
}
