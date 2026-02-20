import AppKit
import Combine
@preconcurrency import MartenMacServices

@MainActor
final class ScreenSharingProtectionCoordinator {
    private let screenSharingManager: ScreenSharingManager
    private var originalWindowSharingTypes: [ObjectIdentifier: NSWindow.SharingType] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(screenSharingManager: ScreenSharingManager) {
        self.screenSharingManager = screenSharingManager
    }

    func start(settingsWindowCloseHandler: (() -> Void)? = nil) {
        applyProtection(isEnabled: screenSharingManager.isScreenSharingModeActive)

        screenSharingManager.$isScreenSharingModeActive
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.applyProtection(isEnabled: isEnabled)
            }
            .store(in: &cancellables)

        let visibilityNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didExposeNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]

        Publishers.MergeMany(
            visibilityNotifications.map { NotificationCenter.default.publisher(for: $0) }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard
                let self,
                let window = notification.object as? NSWindow
            else { return }
            self.applyProtection(
                to: window,
                isEnabled: self.screenSharingManager.isScreenSharingModeActive
            )
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.originalWindowSharingTypes.removeValue(forKey: ObjectIdentifier(window))
                if window.identifier?.rawValue == "settings" {
                    settingsWindowCloseHandler?()
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    private func applyProtection(isEnabled: Bool) {
        for window in NSApp.windows {
            applyProtection(to: window, isEnabled: isEnabled)
        }

        if !isEnabled {
            originalWindowSharingTypes.removeAll()
        }
    }

    private func applyProtection(to window: NSWindow, isEnabled: Bool) {
        let windowID = ObjectIdentifier(window)

        if isEnabled {
            if originalWindowSharingTypes[windowID] == nil {
                originalWindowSharingTypes[windowID] = window.sharingType
            }
            if window.sharingType != .none {
                window.sharingType = .none
            }
            return
        }

        guard let originalSharingType = originalWindowSharingTypes[windowID] else { return }
        if window.sharingType != originalSharingType {
            window.sharingType = originalSharingType
        }
    }
}
