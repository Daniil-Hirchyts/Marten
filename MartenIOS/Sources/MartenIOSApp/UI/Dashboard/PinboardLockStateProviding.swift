import Foundation

@MainActor
protocol PinboardLockStateProviding: AnyObject {
    var isAuthenticating: Bool { get }
    func isLocked(_ pinboardID: UUID) -> Bool
    func canAccess(_ pinboardID: UUID) -> Bool
    func setLock(_ enabled: Bool, for pinboardID: UUID)
    func lockNow(pinboardID: UUID)
    func unlock(pinboardID: UUID, pinboardName: String) async -> Bool
    func reconcile(validPinboardIDs: Set<UUID>)
}

@MainActor
extension PinboardLockStateStore: PinboardLockStateProviding {}
