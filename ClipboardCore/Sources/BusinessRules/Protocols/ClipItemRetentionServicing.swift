import Foundation

public protocol ClipItemRetentionServicing: Sendable {
    func cleanupExpiredItems(policy: RetentionPolicy, now: Date) throws -> Int
}

public extension ClipItemRetentionServicing {
    func cleanupExpiredItems(policy: RetentionPolicy) throws -> Int {
        try cleanupExpiredItems(policy: policy, now: Date())
    }
}
