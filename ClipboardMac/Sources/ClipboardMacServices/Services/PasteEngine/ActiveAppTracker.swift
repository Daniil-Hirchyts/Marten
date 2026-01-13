import AppKit
import Foundation
import OSLog

public final class ActiveAppTracker {
    private var recordedApp: NSRunningApplication?

    public init() {}

    public func recordFrontmostApp() {
        recordedApp = NSWorkspace.shared.frontmostApplication
        Logger.paste.info("Recorded frontmost app: \(self.recordedApp?.bundleIdentifier ?? "unknown")")
    }

    public func reactivateRecordedApp() {
        guard let app = recordedApp else {
            Logger.paste.error("No recorded app to reactivate")
            return
        }

        app.activate(options: .activateIgnoringOtherApps)
    }

    public var recordedBundleID: String? {
        recordedApp?.bundleIdentifier
    }
}
