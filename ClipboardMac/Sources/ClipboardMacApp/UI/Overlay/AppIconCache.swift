import AppKit
import Foundation
import SwiftUI

final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var missingBundleIDs: Set<String> = []
    private let lock = NSLock()

    func cachedIcon(bundleID: String) -> NSImage? {
        cache.object(forKey: bundleID as NSString)
    }

    func hasMissing(bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return missingBundleIDs.contains(bundleID)
    }

    func setMissing(bundleID: String) {
        lock.lock()
        missingBundleIDs.insert(bundleID)
        lock.unlock()
    }

    func setIcon(_ icon: NSImage, bundleID: String) {
        cache.setObject(icon, forKey: bundleID as NSString)
    }
}

final class AppIconLoader: ObservableObject {
    @Published private(set) var icon: NSImage?

    private var loadTask: Task<Void, Never>?

    func load(bundleID: String?) {
        loadTask?.cancel()
        icon = nil

        guard let bundleID, !bundleID.isEmpty else { return }
        if let cached = AppIconCache.shared.cachedIcon(bundleID: bundleID) {
            icon = cached
            return
        }
        if AppIconCache.shared.hasMissing(bundleID: bundleID) {
            return
        }

        loadTask = Task.detached { [weak self] in
            guard let self else { return }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else {
                AppIconCache.shared.setMissing(bundleID: bundleID)
                return
            }
            let loaded = NSWorkspace.shared.icon(forFile: url.path)
            AppIconCache.shared.setIcon(loaded, bundleID: bundleID)
            await MainActor.run {
                self.icon = loaded
            }
        }
    }
}

struct AppIconView: View {
    let bundleID: String?
    let size: CGFloat

    @StateObject private var loader = AppIconLoader()

    init(bundleID: String?, size: CGFloat = 16) {
        self.bundleID = bundleID
        self.size = size
    }

    var body: some View {
        Group {
            if let icon = loader.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .font(.system(size: max(10, size - 4), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loader.load(bundleID: bundleID)
        }
        .onChange(of: bundleID) { newValue, _ in
            loader.load(bundleID: newValue)
        }
    }
}
