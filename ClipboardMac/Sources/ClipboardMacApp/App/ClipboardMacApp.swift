import ClipboardCore
import SwiftUI

@main
struct ClipboardMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some Scene {
        Settings {
            SettingsView(syncCoordinator: appDelegate.services.syncCoordinator)
        }

        Window("Welcome to Paste", id: "onboarding") {
            OnboardingFlow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
