#if os(watchOS)
import Foundation
import WatchConnectivity

/// Receives sync-completion and lock-state events sent by the iPhone over WCSession.
///
/// Call `activate()` once during app startup. Assign `onSyncCompleted` and
/// `onLockStateReceived` before activating so that no events are missed.
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {

    /// Fired when the iPhone signals that an inbound sync has finished.
    var onSyncCompleted: (() -> Void)?

    /// Fired with the updated set of locked pinboard UUIDs when the iPhone pushes lock state.
    var onLockStateReceived: ((Set<UUID>) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // If there is already an application context from a previous session,
        // process it now so the Watch doesn't miss anything while it was off wrist.
        if activationState == .activated {
            dispatch(context: session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        dispatch(context: applicationContext)
    }

    // MARK: - Private

    private func dispatch(context: [String: Any]) {
        guard let event = context["event"] as? String else { return }

        switch event {
        case "syncCompleted":
            let callback = onSyncCompleted
            Task { @MainActor in callback?() }

        case "lockStateChanged":
            let rawIDs = context["lockedIDs"] as? [String] ?? []
            let ids = Set(rawIDs.compactMap(UUID.init(uuidString:)))
            let callback = onLockStateReceived
            Task { @MainActor in callback?(ids) }

        default:
            break
        }
    }
}
#endif
