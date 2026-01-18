import AppKit
import ClipboardMacServices
import Combine
import SwiftUI

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let toggleHandler: () -> Void
    private let hideOverlayHandler: (@escaping () -> Void) -> Void
    private let screenSharingManager: ScreenSharingManager
    private var screenSharingMenuItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []

    init(
        toggleHandler: @escaping () -> Void,
        hideOverlayHandler: @escaping (@escaping () -> Void) -> Void,
        screenSharingManager: ScreenSharingManager
    ) {
        self.toggleHandler = toggleHandler
        self.hideOverlayHandler = hideOverlayHandler
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
        showClipboardItem.image = NSImage(
            systemSymbolName: "clipboard", accessibilityDescription: nil)
        menu.addItem(showClipboardItem)

        if #available(macOS 14.0, *) {
            let settingsItem = NSMenuItem()
            let hostingView = NSHostingView(
                rootView: MenuSettingsButton14(closeOverlay: { [weak self] completion in
                    self?.hideOverlayHandler(completion) ?? completion()
                })
            )
            hostingView.frame.size = NSSize(width: 220, height: 22)
            settingsItem.view = hostingView
            settingsItem.keyEquivalent = ","
            settingsItem.keyEquivalentModifierMask = [.command]
            menu.addItem(settingsItem)
        } else {
            let settingsItem = NSMenuItem(
                title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.target = self
            settingsItem.image = NSImage(
                systemSymbolName: "gearshape", accessibilityDescription: nil)
            menu.addItem(settingsItem)
        }

        menu.addItem(NSMenuItem.separator())

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
        hideOverlayHandler {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@available(macOS 14.0, *)
private struct MenuSettingsButton14: View {
    let closeOverlay: (@escaping () -> Void) -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            closeOverlay {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                Text("Settings…")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 22)
        }
        .buttonStyle(.plain)
    }
}

