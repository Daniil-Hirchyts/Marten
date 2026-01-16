import AppKit
import ClipboardMacServices
import Combine

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let toggleHandler: () -> Void
    private let screenSharingManager: ScreenSharingManager
    private var screenSharingMenuItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    init(
        toggleHandler: @escaping () -> Void,
        screenSharingManager: ScreenSharingManager
    ) {
        self.toggleHandler = toggleHandler
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

        let showClipboardItem = NSMenuItem(
            title: "Show Clipboard", action: #selector(showClipboard), keyEquivalent: "v")
        showClipboardItem.target = self
        showClipboardItem.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
        menu.addItem(showClipboardItem)

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
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
        screenSharingItem.image = NSImage(systemSymbolName: "rectangle.inset.filled.on.rectangle", accessibilityDescription: nil)
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
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func showClipboard() {
        toggleHandler()
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
}
