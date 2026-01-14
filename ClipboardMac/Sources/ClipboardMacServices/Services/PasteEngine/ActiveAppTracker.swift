import AppKit
import Foundation
import OSLog

public final class ActiveAppTracker {
    private var recordedApp: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?
    private let currentBundleID = Bundle.main.bundleIdentifier

    public init() {}

    public func recordFrontmostApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if isSelfApp(frontmost) {
            return
        }
        recordedApp = frontmost
        lastExternalApp = frontmost
        Logger.paste.info("Recorded frontmost app: \(frontmost?.bundleIdentifier ?? "unknown")")
    }

    public func reactivateRecordedApp() {
        guard let app = resolvedTargetApp() else {
            Logger.paste.error("No recorded app to reactivate")
            return
        }
        _ = app.activate(options: .activateIgnoringOtherApps)
    }

    public var recordedBundleID: String? {
        resolvedTargetApp()?.bundleIdentifier
    }

    private func resolvedTargetApp() -> NSRunningApplication? {
        if let recordedApp, !isSelfApp(recordedApp) {
            return recordedApp
        }
        if let lastExternalApp, !isSelfApp(lastExternalApp) {
            return lastExternalApp
        }
        return recordedApp
    }

    private func isSelfApp(_ app: NSRunningApplication?) -> Bool {
        guard let currentBundleID else { return false }
        return app?.bundleIdentifier == currentBundleID
    }
}
