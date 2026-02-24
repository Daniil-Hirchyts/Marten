import Foundation

enum WatchDefaults {
    static let appGroupIdentifier = "group.com.hirchyts.marten"
    static let selectedPinboardIDKey = "marten.watch.selectedPinboardID"
    static let lockHookPinboardIDsKey = "marten.ios.pinboard.lockedIDs"
    static let syncEnabledKey = "com.hirchyts.marten.syncEnabled"

    static func register(_ userDefaults: UserDefaults) {
        userDefaults.register(defaults: [
            selectedPinboardIDKey: "",
            lockHookPinboardIDsKey: [String](),
            syncEnabledKey: true,
        ])
    }
}
