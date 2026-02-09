import Foundation

enum PinboardSecuritySettings {
    static let lockedPinboardIDsKey = "pinboard.lockedPinboardIDs"
    static let unlockDurationSecondsKey = "pinboard.unlockDurationSeconds"
    static let defaultUnlockDurationSeconds = 30
    static let unlockDurationRange: ClosedRange<Int> = 1...300
    static let quickUnlockDurations: [Int] = [15, 30, 60, 120, 300]

    static func clampedUnlockDuration(_ seconds: Int) -> Int {
        min(max(seconds, unlockDurationRange.lowerBound), unlockDurationRange.upperBound)
    }

    static func nearestQuickDuration(to seconds: Int) -> Int {
        let clamped = clampedUnlockDuration(seconds)
        return quickUnlockDurations.min(by: { abs($0 - clamped) < abs($1 - clamped) })
            ?? defaultUnlockDurationSeconds
    }
}
