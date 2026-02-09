import Foundation
import LocalAuthentication
import SwiftUI

protocol PinboardAuthenticationProviding {
    func authenticate(reason: String) async -> Bool
}

struct DeviceOwnerAuthenticationProvider: PinboardAuthenticationProviding {
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
final class PinboardLockController: ObservableObject {
    @Published private(set) var lockedPinboardIDs: Set<UUID>
    @Published private(set) var unlockedPinboardIDs: Set<UUID> = []
    @Published private(set) var isAuthenticating = false

    private let userDefaults: UserDefaults
    private let authenticator: PinboardAuthenticationProviding
    private let transitionAnimation = Animation.easeInOut(duration: 0.2)
    private var unlockExpirations: [UUID: Date] = [:]
    private var expirationTasks: [UUID: Task<Void, Never>] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        authenticator: PinboardAuthenticationProviding = DeviceOwnerAuthenticationProvider()
    ) {
        self.userDefaults = userDefaults
        self.authenticator = authenticator
        self.lockedPinboardIDs = Self.loadLockedPinboardIDs(from: userDefaults)
    }

    deinit {
        expirationTasks.values.forEach { $0.cancel() }
    }

    func isLocked(pinboardID: UUID) -> Bool {
        lockedPinboardIDs.contains(pinboardID)
    }

    func canAccess(pinboardID: UUID) -> Bool {
        guard lockedPinboardIDs.contains(pinboardID) else { return true }
        refreshExpirationIfNeeded(for: pinboardID)
        return unlockedPinboardIDs.contains(pinboardID)
    }

    func remainingUnlockSeconds(pinboardID: UUID) -> Int? {
        guard canAccess(pinboardID: pinboardID), let expiration = unlockExpirations[pinboardID]
        else {
            return nil
        }
        return max(0, Int(ceil(expiration.timeIntervalSinceNow)))
    }

    func setLockEnabled(_ isEnabled: Bool, pinboardID: UUID) {
        withAnimation(transitionAnimation) {
            if isEnabled {
                lockedPinboardIDs.insert(pinboardID)
                clearUnlockedState(for: pinboardID)
            } else {
                lockedPinboardIDs.remove(pinboardID)
                clearUnlockedState(for: pinboardID)
            }
        }
        persistLockedPinboardIDs()
    }

    func lockNow(pinboardID: UUID) {
        guard lockedPinboardIDs.contains(pinboardID) else { return }
        withAnimation(transitionAnimation) {
            clearUnlockedState(for: pinboardID)
        }
    }

    func unlock(pinboardID: UUID, pinboardName: String) async -> Bool {
        guard lockedPinboardIDs.contains(pinboardID) else { return true }
        if canAccess(pinboardID: pinboardID) {
            return true
        }
        guard !isAuthenticating else { return false }

        withAnimation(transitionAnimation) {
            isAuthenticating = true
        }

        let reason = "Unlock \"\(pinboardName)\" in Marten"
        let authenticated = await authenticator.authenticate(reason: reason)

        // Brief delay to let app regain focus before we allow overlay to hide
        try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
        withAnimation(transitionAnimation) {
            isAuthenticating = false
        }

        guard authenticated else { return false }

        applyTemporaryUnlock(for: pinboardID)
        return true
    }

    func reconcile(validPinboardIDs: [UUID]) {
        let validIDs = Set(validPinboardIDs)

        let staleLocked = lockedPinboardIDs.subtracting(validIDs)
        if !staleLocked.isEmpty {
            withAnimation(transitionAnimation) {
                lockedPinboardIDs.subtract(staleLocked)
            }
            persistLockedPinboardIDs()
        }

        for staleID in unlockedPinboardIDs.subtracting(validIDs) {
            clearUnlockedState(for: staleID)
        }
    }

    private func applyTemporaryUnlock(for pinboardID: UUID) {
        let duration = currentUnlockDurationSeconds()
        let expiration = Date().addingTimeInterval(TimeInterval(duration))
        unlockExpirations[pinboardID] = expiration
        withAnimation(transitionAnimation) {
            _ = unlockedPinboardIDs.insert(pinboardID)
        }
        scheduleExpirationTask(for: pinboardID, expiration: expiration)
    }

    private func scheduleExpirationTask(for pinboardID: UUID, expiration: Date) {
        expirationTasks[pinboardID]?.cancel()
        expirationTasks[pinboardID] = Task { [weak self] in
            let seconds = max(0, expiration.timeIntervalSinceNow)
            if seconds > 0 {
                let nanos = UInt64(seconds * 1_000_000_000)
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
        guard currentExpiration <= Date() else { return }
        guard currentExpiration == expectedExpiration else { return }
        clearUnlockedState(for: pinboardID)
    }

    private func clearUnlockedState(for pinboardID: UUID) {
        withAnimation(transitionAnimation) {
            unlockedPinboardIDs.remove(pinboardID)
            unlockExpirations.removeValue(forKey: pinboardID)
            expirationTasks[pinboardID]?.cancel()
            expirationTasks.removeValue(forKey: pinboardID)
        }
    }

    private func refreshExpirationIfNeeded(for pinboardID: UUID) {
        guard let expiration = unlockExpirations[pinboardID] else { return }
        if expiration <= Date() {
            clearUnlockedState(for: pinboardID)
        }
    }

    private func currentUnlockDurationSeconds() -> Int {
        let configured = userDefaults.integer(forKey: PinboardSecuritySettings.unlockDurationSecondsKey)
        if configured == 0 {
            return PinboardSecuritySettings.defaultUnlockDurationSeconds
        }
        return PinboardSecuritySettings.clampedUnlockDuration(configured)
    }

    private func persistLockedPinboardIDs() {
        let raw = lockedPinboardIDs.map(\.uuidString).sorted()
        userDefaults.set(raw, forKey: PinboardSecuritySettings.lockedPinboardIDsKey)
    }

    private static func loadLockedPinboardIDs(from userDefaults: UserDefaults) -> Set<UUID> {
        guard let values = userDefaults.array(forKey: PinboardSecuritySettings.lockedPinboardIDsKey) as? [String]
        else {
            return []
        }
        return Set(values.compactMap(UUID.init(uuidString:)))
    }
}
