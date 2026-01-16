import AppKit
import ClipboardCore
import SwiftUI

@MainActor
final class IgnoredAppsViewModel: ObservableObject {
    @Published private(set) var apps: [IgnoredApp] = []

    private let manager: IgnoredAppsManager

    init(manager: IgnoredAppsManager = IgnoredAppsManager()) {
        self.manager = manager
        refresh()
    }

    func refresh() {
        apps = manager.ignoredApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func addFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else {
            return
        }

        let name =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent)

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let iconData = Self.pngData(from: icon)
        manager.add(
            IgnoredApp(
                bundleIdentifier: bundleIdentifier, name: name, iconData: iconData, addedAt: Date())
        )
        refresh()
    }

    func remove(bundleIdentifier: String) {
        manager.remove(bundleIdentifier: bundleIdentifier)
        refresh()
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
