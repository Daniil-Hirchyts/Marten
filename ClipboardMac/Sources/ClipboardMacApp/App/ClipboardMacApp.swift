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
        .defaultSize(width: 720, height: 520)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("Capture Text (OCR)") {
                    Task { @MainActor in
                        appDelegate.openOCRCapture()
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
