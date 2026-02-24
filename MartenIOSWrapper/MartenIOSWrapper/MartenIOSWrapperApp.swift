//
//  MartenIOSWrapperApp.swift
//  MartenIOSWrapper
//
//  Created by Hirchyts Daniil on 11/02/2026.
//

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
}
#endif

@main
struct MartenIOSWrapperApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(MartenIOSAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
