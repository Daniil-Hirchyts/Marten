import Foundation
import OSLog

/// CrashReporter provides centralized error logging and crash reporting
/// using OSLog for production diagnostics.
public final class CrashReporter: @unchecked Sendable {
    
    public static let shared = CrashReporter()
    
    private let logger = Logger(subsystem: "com.paste.clipboard", category: "crash")
    
    private init() {}
    
    /// Records a non-fatal error that was handled gracefully
    public func recordError(
        _ error: Error,
        context: String,
        additionalInfo: [String: String] = [:]
    ) {
        let errorDescription = "\(error)"
        let info = additionalInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        
        logger.error("""
            [ERROR] Context: \(context)
            Error: \(errorDescription)
            Info: \(info)
            """)
    }
    
    /// Records a critical error that may indicate app instability
    public func recordCriticalError(
        _ error: Error,
        context: String,
        additionalInfo: [String: String] = [:]
    ) {
        let errorDescription = "\(error)"
        let info = additionalInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        
        logger.critical("""
            [CRITICAL] Context: \(context)
            Error: \(errorDescription)
            Info: \(info)
            Thread: \(Thread.current)
            """)
    }
    
    /// Records a fatal error (called just before crash)
    public func recordFatalError(
        _ message: String,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        logger.fault("""
            [FATAL] \(message)
            Location: \(file):\(line) in \(function)
            """)
    }
    
    /// Logs diagnostic information for troubleshooting
    public func logInfo(
        _ message: String,
        context: String,
        additionalInfo: [String: String] = [:]
    ) {
        let info = additionalInfo.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        logger.info("[INFO] \(context): \(message) | \(info)")
    }
    
    /// Logs a warning about a recoverable issue
    public func logWarning(
        _ message: String,
        context: String
    ) {
        logger.warning("[WARNING] \(context): \(message)")
    }
    
    /// Sets up global exception handler (call at app launch)
    public func setupGlobalExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.logger.fault("""
                [UNCAUGHT EXCEPTION]
                Name: \(exception.name.rawValue)
                Reason: \(exception.reason ?? "Unknown")
                Call Stack: \(exception.callStackSymbols.joined(separator: "\n"))
                """)
        }
        
        logger.info("Global exception handler configured")
    }
    
    /// Records app lifecycle event
    public func recordLifecycleEvent(_ event: LifecycleEvent) {
        logger.info("[LIFECYCLE] \(event.rawValue)")
    }
    
    public enum LifecycleEvent: String {
        case appLaunched = "App Launched"
        case appTerminating = "App Terminating"
        case appBecameActive = "App Became Active"
        case appResignedActive = "App Resigned Active"
        case lowMemoryWarning = "Low Memory Warning"
    }
}

/// Extension for recording errors in specific subsystems
extension CrashReporter {
    
    /// Records an error in the clipboard capture subsystem
    public func recordCaptureError(
        _ error: Error,
        operation: String,
        bundleID: String? = nil
    ) {
        var info: [String: String] = ["operation": operation]
        if let bundleID = bundleID {
            info["sourceApp"] = bundleID
        }
        recordError(error, context: "Capture", additionalInfo: info)
    }
    
    /// Records an error in the paste subsystem
    public func recordPasteError(
        _ error: Error,
        operation: String,
        targetApp: String? = nil
    ) {
        var info: [String: String] = ["operation": operation]
        if let targetApp = targetApp {
            info["targetApp"] = targetApp
        }
        recordError(error, context: "Paste", additionalInfo: info)
    }
    
    /// Records an error in the sync subsystem
    public func recordSyncError(
        _ error: Error,
        operation: String,
        isCritical: Bool = false
    ) {
        let info: [String: String] = ["operation": operation]
        if isCritical {
            recordCriticalError(error, context: "Sync", additionalInfo: info)
        } else {
            recordError(error, context: "Sync", additionalInfo: info)
        }
    }
    
    /// Records an error in the database subsystem
    public func recordDatabaseError(
        _ error: Error,
        operation: String,
        entityName: String? = nil
    ) {
        var info: [String: String] = ["operation": operation]
        if let entityName = entityName {
            info["entity"] = entityName
        }
        recordCriticalError(error, context: "Database", additionalInfo: info)
    }
}

/// Helper for wrapping operations with automatic error recording
extension CrashReporter {
    
    /// Executes a throwing operation and logs any errors
    @discardableResult
    public func withErrorLogging<T>(
        context: String,
        operation: () throws -> T
    ) -> Result<T, Error> {
        do {
            let result = try operation()
            return .success(result)
        } catch {
            recordError(error, context: context)
            return .failure(error)
        }
    }
    
    /// Executes an async throwing operation and logs any errors
    @discardableResult
    public func withErrorLogging<T>(
        context: String,
        operation: () async throws -> T
    ) async -> Result<T, Error> {
        do {
            let result = try await operation()
            return .success(result)
        } catch {
            recordError(error, context: context)
            return .failure(error)
        }
    }
}
