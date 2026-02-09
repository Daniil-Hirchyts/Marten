import AppKit
import MartenMacServices
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services: any AppServiceProviding
    private let coordinator: AppCoordinator

    @MainActor
    override init() {
        let services = AppServiceContainer()
        self.services = services
        self.coordinator = AppCoordinator(services: services)
        super.init()
    }

    @MainActor
    init(services: any AppServiceProviding) {
        self.services = services
        self.coordinator = AppCoordinator(services: services)
        super.init()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    @MainActor
    func applicationDidBecomeActive(_ notification: Notification) {
        services.syncCoordinator?.handleAppDidBecomeActive()
    }

    @MainActor
    func applicationWillResignActive(_ notification: Notification) {
        services.syncCoordinator?.handleAppWillResignActive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Prevent clicking the dock icon from re-showing the settings window.
        true
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Logger.app.info("Registered for remote notifications")
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.app.error(
            "Failed to register for remote notifications: \(error.localizedDescription)"
        )
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        Task {
            await coordinator.handleRemoteNotification(userInfo)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    @MainActor
    @objc func openSettingsWindow() {
        coordinator.openSettings()
    }

    @MainActor
    @objc func openNewTextItem() {
        coordinator.openNewTextItem()
    }

    @MainActor
    @objc func openOCRCapture() {
        coordinator.startOCRCapture()
    }
}

// SAFETY: AppDelegate is UI-owned and only used from the main actor.
@MainActor
extension AppDelegate: @unchecked Sendable {}
