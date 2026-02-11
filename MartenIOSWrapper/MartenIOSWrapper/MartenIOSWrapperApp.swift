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
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: MartenIOSNotifications.cloudKitShareAccepted,
            object: metadata
        )
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
