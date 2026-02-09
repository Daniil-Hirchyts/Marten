import Foundation

struct SyncStateMachine {
    private(set) var status: SyncStatus = .idle
    private(set) var progress: SyncProgress = .zero

    mutating func transition(to newStatus: SyncStatus) {
        status = newStatus
    }

    mutating func updateProgress(_ newProgress: SyncProgress) {
        progress = newProgress
    }
}
