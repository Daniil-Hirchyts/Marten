import Foundation
import LocalAuthentication

protocol WatchPinboardAuthenticationProviding: Sendable {
    func authenticate(reason: String) async -> Bool
}

struct DeviceOwnerWatchAuthenticationProvider: WatchPinboardAuthenticationProviding {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                success,
                _ in
                continuation.resume(returning: success)
            }
        }
    }
}

@MainActor
@Observable
final class WatchPinboardLockStateStore {
    private(set) var lockedPinboardIDs: Set<UUID>
    private(set) var unlockedPinboardIDs: Set<UUID> = []
    private(set) var isAuthenticating = false

    private let userDefaults: UserDefaults
    private let authenticator: any WatchPinboardAuthenticationProviding
    private let unlockDurationSeconds: Int

    private var unlockExpirations: [UUID: Date] = [:]
    private var expirationTasks: [UUID: Task<Void, Never>] = [:]

    init(
        userDefaults: UserDefaults,
        authenticator: any WatchPinboardAuthenticationProviding = DeviceOwnerWatchAuthenticationProvider(),
        unlockDurationSeconds: Int = 30
    ) {
        self.userDefaults = userDefaults
        self.authenticator = authenticator
        self.unlockDurationSeconds = max(1, unlockDurationSeconds)
        self.lockedPinboardIDs = Self.loadLockedIDs(from: userDefaults)
    }

    func isLocked(_ pinboardID: UUID) -> Bool {
        lockedPinboardIDs.contains(pinboardID)
    }

    func canAccess(_ pinboardID: UUID) -> Bool {
        guard lockedPinboardIDs.contains(pinboardID) else { return true }
        refreshExpirationIfNeeded(for: pinboardID)
        return unlockedPinboardIDs.contains(pinboardID)
    }

    func unlock(pinboardID: UUID, pinboardName: String) async -> Bool {
        guard lockedPinboardIDs.contains(pinboardID) else { return true }
        if canAccess(pinboardID) {
            return true
        }
        guard !isAuthenticating else { return false }

        isAuthenticating = true
        let reason = "Unlock \"\(pinboardName)\" in Marten"
        let authenticated = await authenticator.authenticate(reason: reason)
        isAuthenticating = false

        guard authenticated else { return false }
        applyTemporaryUnlock(for: pinboardID)
        return true
    }

    func replaceLockedPinboardIDs(_ ids: Set<UUID>) {
        lockedPinboardIDs = ids

        for unlockedID in unlockedPinboardIDs where !ids.contains(unlockedID) {
            clearUnlockedState(for: unlockedID)
        }

        persist()
    }

    func reconcile(validPinboardIDs: Set<UUID>) {
        let staleLocked = lockedPinboardIDs.subtracting(validPinboardIDs)
        if !staleLocked.isEmpty {
            lockedPinboardIDs.subtract(staleLocked)
            persist()
        }

        for staleID in unlockedPinboardIDs.subtracting(validPinboardIDs) {
            clearUnlockedState(for: staleID)
        }
    }

    private func applyTemporaryUnlock(for pinboardID: UUID) {
        let expiration = Date().addingTimeInterval(TimeInterval(unlockDurationSeconds))
        unlockedPinboardIDs.insert(pinboardID)
        unlockExpirations[pinboardID] = expiration
        scheduleExpirationTask(for: pinboardID, expiration: expiration)
    }

    private func scheduleExpirationTask(for pinboardID: UUID, expiration: Date) {
        expirationTasks[pinboardID]?.cancel()
        expirationTasks[pinboardID] = Task { [weak self] in
            let remainingSeconds = max(0, expiration.timeIntervalSinceNow)
            if remainingSeconds > 0 {
                let nanos = UInt64(remainingSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.expireUnlockIfNeeded(for: pinboardID, expectedExpiration: expiration)
            }
        }
    }

    private func expireUnlockIfNeeded(for pinboardID: UUID, expectedExpiration: Date) {
        guard let currentExpiration = unlockExpirations[pinboardID] else { return }
        guard currentExpiration == expectedExpiration else { return }
        guard currentExpiration <= Date() else { return }
        clearUnlockedState(for: pinboardID)
    }

    private func clearUnlockedState(for pinboardID: UUID) {
        unlockedPinboardIDs.remove(pinboardID)
        unlockExpirations.removeValue(forKey: pinboardID)
        expirationTasks[pinboardID]?.cancel()
        expirationTasks.removeValue(forKey: pinboardID)
    }

    private func refreshExpirationIfNeeded(for pinboardID: UUID) {
        guard let expiration = unlockExpirations[pinboardID] else { return }
        if expiration <= Date() {
            clearUnlockedState(for: pinboardID)
        }
    }

    private func persist() {
        let raw = lockedPinboardIDs.map(\.uuidString).sorted()
        userDefaults.set(raw, forKey: WatchDefaults.lockHookPinboardIDsKey)
    }

    private static func loadLockedIDs(from userDefaults: UserDefaults) -> Set<UUID> {
        guard
            let raw = userDefaults.array(forKey: WatchDefaults.lockHookPinboardIDsKey) as? [String]
        else {
            return []
        }

        return Set(raw.compactMap(UUID.init(uuidString:)))
    }
}
