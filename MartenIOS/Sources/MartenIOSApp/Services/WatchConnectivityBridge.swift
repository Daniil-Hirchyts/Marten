#if os(iOS)
import Foundation
import WatchConnectivity

/// Sends sync-completion and lock-state events to the paired Apple Watch via WCSession.
///
/// Keeps the Watch from having to wait for the next CloudKit push or 15-second poll.
/// Activate once during app startup; subsequent calls to `notifyWatchSyncCompleted()` and
/// `pushLockState(_:)` are safe to call on any thread.
@MainActor
public final class WatchConnectivityBridge: NSObject, WCSessionDelegate, @unchecked Sendable {

    public static let shared = WatchConnectivityBridge()

    public override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Notifies the Watch that an inbound sync completed so it can pull fresh data.
    public func notifyWatchSyncCompleted() {
        send(context: ["event": "syncCompleted", "timestamp": Date().timeIntervalSinceReferenceDate])
    }

    /// Pushes the current set of locked pinboard IDs to the Watch.
    public func pushLockState(_ lockedIDs: Set<UUID>) {
        let raw = lockedIDs.map(\.uuidString)
        send(context: ["event": "lockStateChanged", "lockedIDs": raw])
    }

    // MARK: - Private

    private func send(context: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            // Best-effort: context delivery is not critical.
        }
    }

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after Watch handoff.
        WCSession.default.activate()
    }
}
#endif
