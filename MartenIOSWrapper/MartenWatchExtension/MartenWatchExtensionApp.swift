import CloudKit
import MartenWatchApp
import SwiftUI
import WatchKit

final class MartenWatchExtensionDelegate: NSObject, WKExtensionDelegate {
    func applicationDidFinishLaunching() {
        WKExtension.shared().registerForRemoteNotifications()
    }

    func didReceiveRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (WKBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        NotificationCenter.default.post(
            name: MartenWatchNotifications.cloudKitRemoteChangeReceived,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }
}

@main
struct MartenWatchExtensionApp: App {
    @WKExtensionDelegateAdaptor(MartenWatchExtensionDelegate.self) private var extensionDelegate

    var body: some Scene {
        WindowGroup {
            MartenWatchRootView()
        }
    }
}
