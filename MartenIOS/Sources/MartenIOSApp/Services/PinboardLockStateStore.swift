import Foundation
import LocalAuthentication
import MartenCore

public protocol PinboardAuthenticationProviding: Sendable {
    func authenticate(reason: String) async -> Bool
}

public struct DeviceOwnerAuthenticationProvider: PinboardAuthenticationProviding {
    public init() {}

    public func authenticate(reason: String) async -> Bool {
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
public final class PinboardLockStateStore {
    public private(set) var lockedPinboardIDs: Set<UUID>
    public private(set) var unlockedPinboardIDs: Set<UUID> = []
    public private(set) var isAuthenticating = false

    private let userDefaults: UserDefaults
    private let authenticator: any PinboardAuthenticationProviding
    private let lockStateSynchronizer: (any PinboardLockStateSynchronizing)?
    private let unlockDurationSeconds: Int

    private var unlockExpirations: [UUID: Date] = [:]
    private var expirationTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        userDefaults: UserDefaults = .standard,
        authenticator: any PinboardAuthenticationProviding = DeviceOwnerAuthenticationProvider(),
        lockStateSynchronizer: (any PinboardLockStateSynchronizing)? = ICloudLockStateSynchronizer(),
        unlockDurationSeconds: Int = 30
    ) {
        let persistedLockedIDs = Self.loadLockedIDs(from: userDefaults)
        let synchronizedIDs = lockStateSynchronizer?.latestLockedPinboardIDs()

        self.userDefaults = userDefaults
        self.authenticator = authenticator
        self.lockStateSynchronizer = lockStateSynchronizer
        self.unlockDurationSeconds = max(1, unlockDurationSeconds)
        self.lockedPinboardIDs = synchronizedIDs ?? persistedLockedIDs

        persistLocalState()
        if synchronizedIDs == nil {
            lockStateSynchronizer?.publish(lockedPinboardIDs: lockedPinboardIDs)
        }

        lockStateSynchronizer?.startObserving { [weak self] lockedIDs in
            Task { @MainActor [weak self] in
                self?.applyExternalLockedPinboardIDs(lockedIDs)
            }
        }
    }

    public func isLocked(_ pinboardID: UUID) -> Bool {
        lockedPinboardIDs.contains(pinboardID)
    }

    public func canAccess(_ pinboardID: UUID) -> Bool {
        guard lockedPinboardIDs.contains(pinboardID) else { return true }
        refreshExpirationIfNeeded(for: pinboardID)
        return unlockedPinboardIDs.contains(pinboardID)
    }

    public func setLock(_ enabled: Bool, for pinboardID: UUID) {
        if enabled {
            lockedPinboardIDs.insert(pinboardID)
            clearUnlockedState(for: pinboardID)
        } else {
            lockedPinboardIDs.remove(pinboardID)
            clearUnlockedState(for: pinboardID)
        }
        persistAndBroadcast()
    }

    public func toggleLock(for pinboardID: UUID) {
        setLock(!isLocked(pinboardID), for: pinboardID)
    }

    public func lockNow(pinboardID: UUID) {
        guard lockedPinboardIDs.contains(pinboardID) else { return }
        clearUnlockedState(for: pinboardID)
    }

    public func unlock(pinboardID: UUID, pinboardName: String) async -> Bool {
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

    public func reconcile(validPinboardIDs: Set<UUID>) {
        let staleLocked = lockedPinboardIDs.subtracting(validPinboardIDs)
        if !staleLocked.isEmpty {
            lockedPinboardIDs.subtract(staleLocked)
            persistAndBroadcast()
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

    private func persistAndBroadcast() {
        persistLocalState()
        lockStateSynchronizer?.publish(lockedPinboardIDs: lockedPinboardIDs)
    }

    private func persistLocalState() {
        let raw = lockedPinboardIDs.map(\.uuidString).sorted()
        userDefaults.set(raw, forKey: MartenIOSDefaults.lockHookPinboardIDsKey)
    }

    private func applyExternalLockedPinboardIDs(_ ids: Set<UUID>) {
        guard ids != lockedPinboardIDs else { return }
        lockedPinboardIDs = ids

        for unlockedID in unlockedPinboardIDs where !ids.contains(unlockedID) {
            clearUnlockedState(for: unlockedID)
        }

        persistLocalState()
    }

    private static func loadLockedIDs(from userDefaults: UserDefaults) -> Set<UUID> {
        guard
            let raw = userDefaults.array(forKey: MartenIOSDefaults.lockHookPinboardIDsKey) as? [String]
        else {
            return []
        }

        return Set(raw.compactMap(UUID.init(uuidString:)))
    }
}
