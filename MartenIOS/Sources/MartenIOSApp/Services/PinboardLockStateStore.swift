import Foundation

@MainActor
@Observable
public final class PinboardLockStateStore {
    public private(set) var lockedPinboardIDs: Set<UUID>

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.lockedPinboardIDs = Self.loadLockedIDs(from: userDefaults)
    }

    public func isLocked(_ pinboardID: UUID) -> Bool {
        lockedPinboardIDs.contains(pinboardID)
    }

    public func setLock(_ enabled: Bool, for pinboardID: UUID) {
        if enabled {
            lockedPinboardIDs.insert(pinboardID)
        } else {
            lockedPinboardIDs.remove(pinboardID)
        }
        persist()
    }

    public func toggleLock(for pinboardID: UUID) {
        setLock(!isLocked(pinboardID), for: pinboardID)
    }

    public func reconcile(validPinboardIDs: Set<UUID>) {
        let stale = lockedPinboardIDs.subtracting(validPinboardIDs)
        guard !stale.isEmpty else { return }
        lockedPinboardIDs.subtract(stale)
        persist()
    }

    private func persist() {
        let raw = lockedPinboardIDs.map(\.uuidString).sorted()
        userDefaults.set(raw, forKey: MartenIOSDefaults.lockHookPinboardIDsKey)
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
