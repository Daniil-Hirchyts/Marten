import Foundation

public protocol PinboardLockStateSynchronizing: AnyObject {
    func publish(lockedPinboardIDs: Set<UUID>)
    func latestLockedPinboardIDs() -> Set<UUID>?
    func startObserving(_ onChange: @escaping @Sendable (Set<UUID>) -> Void)
    func stopObserving()
}

public final class ICloudLockStateSynchronizer: PinboardLockStateSynchronizing, @unchecked Sendable {
    public static let lockStateKey = "marten.pinboard.lockedIDs.v1"

    private let store: NSUbiquitousKeyValueStore
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    public init(
        store: NSUbiquitousKeyValueStore = .default,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
    }

    deinit {
        stopObserving()
    }

    public func publish(lockedPinboardIDs: Set<UUID>) {
        let raw = lockedPinboardIDs.map(\.uuidString).sorted()
        store.set(raw, forKey: Self.lockStateKey)
        store.synchronize()
    }

    public func latestLockedPinboardIDs() -> Set<UUID>? {
        guard let raw = store.array(forKey: Self.lockStateKey) as? [String] else {
            return nil
        }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    public func startObserving(_ onChange: @escaping @Sendable (Set<UUID>) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }

        observer = notificationCenter.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }

            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            if let changedKeys, changedKeys.contains(Self.lockStateKey) == false {
                return
            }

            guard let lockedIDs = self.latestLockedPinboardIDs() else { return }
            onChange(lockedIDs)
        }

        store.synchronize()
        if let initial = latestLockedPinboardIDs() {
            onChange(initial)
        }
    }

    public func stopObserving() {
        lock.lock()
        defer { lock.unlock() }

        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }
}
