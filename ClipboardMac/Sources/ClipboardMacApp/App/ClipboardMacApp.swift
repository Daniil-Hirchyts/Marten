import ClipboardCore
import SwiftUI

@main
struct ClipboardMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Paste", id: "settings") {
            SettingsView(syncCoordinator: appDelegate.services.syncCoordinator)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // Remove sidebar toggle from View menu
            CommandGroup(replacing: .sidebar) {}
        }
    }
}
