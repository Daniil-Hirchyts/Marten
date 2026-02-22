import Foundation
import MartenCore

#if canImport(UIKit)
import UIKit
#endif

protocol DashboardClipboardWriting {
    func setString(_ string: String)
}

struct SystemDashboardClipboardWriter: DashboardClipboardWriting {
    func setString(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }
}

protocol DashboardFileManaging {
    func fileExists(atPath path: String) -> Bool
}

struct SystemDashboardFileManager: DashboardFileManaging {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

protocol DashboardImageLoading {
    func loadImage(atPath path: String) -> Any?
}

struct SystemDashboardImageLoader: DashboardImageLoading {
    func loadImage(atPath path: String) -> Any? {
        #if canImport(UIKit)
        return UIImage(contentsOfFile: path)
        #else
        return nil
        #endif
    }
}

struct DashboardDependencies {
    var clipboardWriter: any DashboardClipboardWriting
    var fileManager: any DashboardFileManaging
    var imageLoader: any DashboardImageLoading

    static let live = DashboardDependencies(
        clipboardWriter: SystemDashboardClipboardWriter(),
        fileManager: SystemDashboardFileManager(),
        imageLoader: SystemDashboardImageLoader()
    )
}

