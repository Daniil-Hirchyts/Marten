import Foundation

final class CloudKitOperationContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        var pendingResultToResume: Result<Value, Error>?

        lock.lock()
        if let pendingResult {
            pendingResultToResume = pendingResult
            self.pendingResult = nil
        } else if !isResolved {
            self.continuation = continuation
        }
        lock.unlock()

        if let pendingResultToResume {
            continuation.resume(with: pendingResultToResume)
        }
    }

    func resume(with result: Result<Value, Error>) {
        var continuationToResume: CheckedContinuation<Value, Error>?

        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }

        isResolved = true
        if let continuation {
            continuationToResume = continuation
            self.continuation = nil
        } else {
            pendingResult = result
        }
        lock.unlock()

        continuationToResume?.resume(with: result)
    }
}
