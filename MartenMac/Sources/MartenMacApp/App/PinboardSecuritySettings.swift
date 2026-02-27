import Foundation

enum PinboardSecuritySettings {
    static let canonicalLockedPinboardIDsKey = "marten.ios.pinboard.lockedIDs"
    static let legacyLockedPinboardIDsKey = "pinboard.lockedPinboardIDs"
    static let lockedPinboardIDsKey = canonicalLockedPinboardIDsKey
    static let unlockDurationSecondsKey = "pinboard.unlockDurationSeconds"
    static let defaultUnlockDurationSeconds = 30
    static let unlockDurationRange: ClosedRange<Int> = 1...300
    static let quickUnlockDurations: [Int] = [15, 30, 60, 120, 300]

    static func migrateLockedPinboardIDsIfNeeded(_ userDefaults: UserDefaults) {
        let canonicalValues =
            (userDefaults.array(forKey: canonicalLockedPinboardIDsKey) as? [String]) ?? []
        let legacyValues = (userDefaults.array(forKey: legacyLockedPinboardIDsKey) as? [String]) ?? []
        guard canonicalValues.isEmpty == false || legacyValues.isEmpty == false else {
            return
        }

        let merged = Set((canonicalValues + legacyValues).compactMap(UUID.init(uuidString:))).map(\.uuidString).sorted()
        if merged != canonicalValues {
            userDefaults.set(merged, forKey: canonicalLockedPinboardIDsKey)
        }

        if userDefaults.object(forKey: legacyLockedPinboardIDsKey) != nil {
            userDefaults.removeObject(forKey: legacyLockedPinboardIDsKey)
        }
    }

    static func clampedUnlockDuration(_ seconds: Int) -> Int {
        min(max(seconds, unlockDurationRange.lowerBound), unlockDurationRange.upperBound)
    }

    static func nearestQuickDuration(to seconds: Int) -> Int {
        let clamped = clampedUnlockDuration(seconds)
        return quickUnlockDurations.min(by: { abs($0 - clamped) < abs($1 - clamped) })
            ?? defaultUnlockDurationSeconds
    }
}
