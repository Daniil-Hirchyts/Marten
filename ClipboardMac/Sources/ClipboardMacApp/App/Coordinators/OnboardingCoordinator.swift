import AppKit
import SwiftUI

@MainActor
final class OnboardingCoordinator {
    private var onboardingWindow: NSWindow?

    func startIfNeeded() {
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindowIfNeeded()
        }
    }

    private func showOnboardingWindowIfNeeded() {
        guard onboardingWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Paste"
        window.isReleasedWhenClosed = false
        window.center()

        let hosting = NSHostingController(
            rootView: OnboardingFlow(onClose: { [weak window, weak self] in
                window?.close()
                self?.onboardingWindow = nil
            })
        )
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
