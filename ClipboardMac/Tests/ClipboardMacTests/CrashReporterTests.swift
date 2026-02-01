import XCTest
@testable import ClipboardMacServices

final class CrashReporterTests: XCTestCase {
    
    func testSharedInstanceExists() {
        XCTAssertNotNil(CrashReporter.shared)
    }
    
    func testRecordErrorDoesNotThrow() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertNoThrow(
            CrashReporter.shared.recordError(
                error,
                context: "Test",
                additionalInfo: ["key": "value"]
            )
        )
    }
    
    func testRecordCriticalErrorDoesNotThrow() {
        let error = NSError(domain: "test", code: 2, userInfo: nil)
        XCTAssertNoThrow(
            CrashReporter.shared.recordCriticalError(
                error,
                context: "Critical Test"
            )
        )
    }
    
    func testRecordFatalErrorDoesNotThrow() {
        XCTAssertNoThrow(
            CrashReporter.shared.recordFatalError("Test fatal error")
        )
    }
    
    func testLogInfoDoesNotThrow() {
        XCTAssertNoThrow(
            CrashReporter.shared.logInfo(
                "Test message",
                context: "Test Context"
            )
        )
    }
    
    func testLogWarningDoesNotThrow() {
        XCTAssertNoThrow(
            CrashReporter.shared.logWarning(
                "Test warning",
                context: "Test Context"
            )
        )
    }
    
    func testSetupGlobalExceptionHandlerDoesNotThrow() {
        XCTAssertNoThrow(
            CrashReporter.shared.setupGlobalExceptionHandler()
        )
    }
    
    func testRecordLifecycleEvent() {
        XCTAssertNoThrow(
            CrashReporter.shared.recordLifecycleEvent(.appLaunched)
        )
        XCTAssertNoThrow(
            CrashReporter.shared.recordLifecycleEvent(.appTerminating)
        )
    }
    
    func testRecordCaptureError() {
        let error = NSError(domain: "capture", code: 1, userInfo: nil)
        XCTAssertNoThrow(
            CrashReporter.shared.recordCaptureError(
                error,
                operation: "Test Capture",
                bundleID: "com.test.app"
            )
        )
    }
    
    func testRecordPasteError() {
        let error = NSError(domain: "paste", code: 1, userInfo: nil)
        XCTAssertNoThrow(
            CrashReporter.shared.recordPasteError(
                error,
                operation: "Test Paste",
                targetApp: "com.test.target"
            )
        )
    }
    
    func testRecordSyncError() {
        let error = NSError(domain: "sync", code: 1, userInfo: nil)
        XCTAssertNoThrow(
            CrashReporter.shared.recordSyncError(
                error,
                operation: "Test Sync"
            )
        )
    }
    
    func testRecordDatabaseError() {
        let error = NSError(domain: "database", code: 1, userInfo: nil)
        XCTAssertNoThrow(
            CrashReporter.shared.recordDatabaseError(
                error,
                operation: "Test DB",
                entityName: "ClipItem"
            )
        )
    }
    
    func testWithErrorLoggingSyncSuccess() {
        let result = CrashReporter.shared.withErrorLogging(context: "Test") {
            return "Success"
        }
        
        switch result {
        case .success(let value):
            XCTAssertEqual(value, "Success")
        case .failure:
            XCTFail("Should not fail")
        }
    }
    
    func testWithErrorLoggingSyncFailure() {
        let result = CrashReporter.shared.withErrorLogging(context: "Test") {
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        
        switch result {
        case .success:
            XCTFail("Should fail")
        case .failure(let error):
            XCTAssertEqual((error as NSError).domain, "test")
        }
    }
    
    func testWithErrorLoggingAsyncSuccess() async {
        let result = await CrashReporter.shared.withErrorLogging(context: "Test") {
            return "Async Success"
        }
        
        switch result {
        case .success(let value):
            XCTAssertEqual(value, "Async Success")
        case .failure:
            XCTFail("Should not fail")
        }
    }
    
    func testWithErrorLoggingAsyncFailure() async {
        let result = await CrashReporter.shared.withErrorLogging(context: "Test") {
            throw NSError(domain: "async", code: 1, userInfo: nil)
        }
        
        switch result {
        case .success:
            XCTFail("Should fail")
        case .failure(let error):
            XCTAssertEqual((error as NSError).domain, "async")
        }
    }
}
