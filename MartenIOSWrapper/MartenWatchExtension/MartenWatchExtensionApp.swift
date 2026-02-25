import CloudKit
import MartenWatchApp
import SwiftUI
import WatchKit

final class MartenWatchExtensionDelegate: NSObject, WKExtensionDelegate {
    private static let backgroundRefreshInterval: TimeInterval = 15 * 60 // 15 minutes

    func applicationDidFinishLaunching() {
        WKExtension.shared().registerForRemoteNotifications()
        scheduleNextBackgroundRefresh()
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

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                // Post a notification so the container can trigger an inbound sync
                NotificationCenter.default.post(
                    name: MartenWatchNotifications.cloudKitRemoteChangeReceived,
                    object: nil
                )
                scheduleNextBackgroundRefresh()
                refreshTask.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func scheduleNextBackgroundRefresh() {
        let preferredDate = Date(timeIntervalSinceNow: Self.backgroundRefreshInterval)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error {
                print("[MartenWatch] Failed to schedule background refresh: \(error.localizedDescription)")
            }
        }
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
