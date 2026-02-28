//
//  MartenIOSWrapperApp.swift
//  MartenIOSWrapper
//
//  Created by Hirchyts Daniil on 11/02/2026.
//

import BackgroundTasks
import CloudKit
import MartenIOSApp
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
final class MartenIOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.hirchyts.marten.sync", using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: task)
        }
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let delegate = Unmanaged<MartenIOSAppDelegate>.fromOpaque(observer).takeUnretainedValue()
                delegate.handleExtensionSyncRequest()
            },
            "com.hirchyts.marten.extension.saved" as CFString,
            nil,
            .deliverImmediately
        )
        
        return true
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: MartenIOSNotifications.cloudKitShareAccepted,
            object: metadata
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        NotificationCenter.default.post(
            name: MartenIOSNotifications.cloudKitRemoteChangeReceived,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        let syncTask = Task { @MainActor in
            let config = MartenIOSStorageConfiguration()
            if let _ = try? config.makePersistenceController() {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        
        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    public func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.hirchyts.marten.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleExtensionSyncRequest() {
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ExtensionSync") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        
        Task { @MainActor in
            let config = MartenIOSStorageConfiguration()
            if let _ = try? config.makePersistenceController() {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
    }
}
#endif

@main
struct MartenIOSWrapperApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(MartenIOSAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if canImport(UIKit)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                appDelegate.scheduleAppRefresh()
            }
        }
        #endif
    }
}
