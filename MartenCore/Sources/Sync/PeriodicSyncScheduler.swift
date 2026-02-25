import Foundation

final class PeriodicSyncScheduler {
    private var task: Task<Void, Never>?

    func start(interval: TimeInterval, runImmediately: Bool = false, action: @escaping @Sendable () async -> Void) {
        stop()

        task = Task {
            if runImmediately {
                guard !Task.isCancelled else { return }
                await action()
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
