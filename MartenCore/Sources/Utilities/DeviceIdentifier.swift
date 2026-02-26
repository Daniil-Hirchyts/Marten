import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(WatchKit)
import WatchKit
#endif

/// Cross-platform utility that returns the current device's user-facing name.
public enum DeviceIdentifier {
    /// The user-facing name of the current device (e.g. "Daniel's MacBook Pro").
    public static var currentDeviceName: String {
        #if os(watchOS)
        return WKInterfaceDevice.current().name
        #elseif os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
}
