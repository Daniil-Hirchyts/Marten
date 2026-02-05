import Foundation

#if DEBUG
import os

enum OverlayPerformanceSignposts {
    static let signposter = OSSignposter(subsystem: "com.paste", category: "Overlay")
    private static let clock = ContinuousClock()

    static func measure<T>(_ name: StaticString, _ operation: () -> T) -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        let start = clock.now
        defer {
            signposter.endInterval(name, state)
            let duration = start.duration(to: clock.now)
            let seconds = Int64(duration.components.seconds)
            let attoseconds = Int64(duration.components.attoseconds)
            let ns = UInt64(max(0, (seconds * 1_000_000_000) + (attoseconds / 1_000_000_000)))
            Task { @MainActor in
                OverlayPerfMetrics.shared.recordOperation(name: String(describing: name), durationNs: ns)
            }
        }
        return operation()
    }

    static func measure<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        let start = clock.now
        defer {
            signposter.endInterval(name, state)
            let duration = start.duration(to: clock.now)
            let seconds = Int64(duration.components.seconds)
            let attoseconds = Int64(duration.components.attoseconds)
            let ns = UInt64(max(0, (seconds * 1_000_000_000) + (attoseconds / 1_000_000_000)))
            Task { @MainActor in
                OverlayPerfMetrics.shared.recordOperation(name: String(describing: name), durationNs: ns)
            }
        }
        return try await operation()
    }
}
#else
enum OverlayPerformanceSignposts {
    static func measure<T>(_ name: StaticString, _ operation: () -> T) -> T {
        operation()
    }

    static func measure<T>(_ name: StaticString, _ operation: () async throws -> T) async rethrows -> T {
        try await operation()
    }
}
#endif
