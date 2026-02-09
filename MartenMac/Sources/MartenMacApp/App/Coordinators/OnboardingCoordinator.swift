import AppKit
import MartenMacServices
import SwiftUI

@MainActor
final class OnboardingCoordinator {
    private let onWindowClosed: (() -> Void)?
    private let permissionManager: PermissionManager
    private var onboardingWindow: NSWindow?

    init(permissionManager: PermissionManager, onWindowClosed: (() -> Void)? = nil) {
        self.permissionManager = permissionManager
        self.onWindowClosed = onWindowClosed
    }

    func startIfNeeded() {
        let shouldForceOnboarding = CommandLine.arguments.contains("-resetOnboarding")
        if shouldForceOnboarding || !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindowIfNeeded()
        }
    }

    private func showOnboardingWindowIfNeeded() {
        guard onboardingWindow == nil else { return }
        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Marten Setup"
        window.identifier = NSUserInterfaceItemIdentifier("onboarding")
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isMovable = true
        window.hasShadow = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        centerWindowOnActiveScreen(window)

        let hosting = NSHostingController(
            rootView: OnboardingFlow(permissionManager: permissionManager, onClose: { [weak window, weak self] in
                window?.close()
                self?.onboardingWindow = nil
                self?.onWindowClosed?()
            })
        )
        window.contentViewController = hosting
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func centerWindowOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let targetScreen else {
            window.center()
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let windowFrame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - windowFrame.width / 2,
            y: visibleFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}

private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
