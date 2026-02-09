@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import Foundation
import OSLog

@MainActor
final class IntegrityCheckService {
    private let clipItemStore: ClipItemStore

    init(clipItemStore: ClipItemStore) {
        self.clipItemStore = clipItemStore
    }

    func runStartupCheck() {
        Logger.integrity.info("Starting startup integrity check")

        do {
            let recentItems = try clipItemStore.fetchRecentItems(limit: 1)
            Logger.integrity.info(
                "Database access verified. Found \(recentItems.count) recent items.")
            CrashReporter.shared.logInfo(
                "Database verified with \(recentItems.count) items",
                context: "Startup Integrity"
            )
        } catch {
            Logger.integrity.fault(
                "Critical: Database access failed during integrity check: \(error.localizedDescription)"
            )
            CrashReporter.shared.recordDatabaseError(
                error,
                operation: "Startup Integrity Check",
                entityName: "ClipItem"
            )
        }

        let rawPolicy = UserDefaults.standard.string(forKey: "retentionPolicy")
        if let raw = rawPolicy, RetentionPolicy(rawValue: raw) == nil {
            Logger.integrity.error(
                "Invalid retention policy found in UserDefaults: \(raw). Defaulting to month."
            )
            CrashReporter.shared.logWarning(
                "Invalid retention policy: \(raw)",
                context: "Startup Integrity"
            )
        } else {
            Logger.integrity.info("Retention policy verified: \(rawPolicy ?? "default")")
        }

        Logger.integrity.info("Startup integrity check completed")
    }
}
