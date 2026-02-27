import AppKit
import CoreImage
import Foundation
import MartenCore
import SwiftUI

final class AppIconCache {
    static let shared = AppIconCache()
    static let martenCardAccentHex = "#FF2E00"

    private static let martenCardAccentColor = NSColor(hex: martenCardAccentHex)

    private let cache = NSCache<NSString, NSImage>()
    private let colorCache = NSCache<NSString, NSColor>()
    private var missingBundleIDs: Set<String> = []
    private var missingColorBundleIDs: Set<String> = []
    private let lock = NSLock()

    func cachedIcon(bundleID: String) -> NSImage? {
        cache.object(forKey: bundleID as NSString)
    }

    func cachedColor(bundleID: String) -> NSColor? {
        if let preferred = Self.preferredColor(for: bundleID) {
            return preferred
        }
        return colorCache.object(forKey: bundleID as NSString)
    }

    static func preferredColor(for bundleID: String) -> NSColor? {
        guard bundleID.isMartenBundleIdentifier else { return nil }
        return martenCardAccentColor
    }

    func hasMissing(bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return missingBundleIDs.contains(bundleID)
    }

    func hasMissingColor(bundleID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return missingColorBundleIDs.contains(bundleID)
    }

    func setMissing(bundleID: String) {
        lock.lock()
        missingBundleIDs.insert(bundleID)
        lock.unlock()
    }

    func setMissingColor(bundleID: String) {
        lock.lock()
        missingColorBundleIDs.insert(bundleID)
        lock.unlock()
    }

    func setIcon(_ icon: NSImage, bundleID: String) {
        cache.setObject(icon, forKey: bundleID as NSString)
    }

    func setColor(_ color: NSColor, bundleID: String) {
        colorCache.setObject(color, forKey: bundleID as NSString)
    }
}

enum SourceAppIdentityResolver {
    static func normalized(_ value: String?) -> String? {
        SourceAppIdentity.normalized(value)
    }

    static func isMartenAppName(_ appName: String?) -> Bool {
        SourceAppIdentity.isMartenSource(bundleID: nil, appName: appName)
    }

    static func resolvedBundleID(bundleID: String?, appName: String?) -> String? {
        SourceAppIdentity.resolvedBundleID(bundleID: bundleID, appName: appName)
    }

    static func isMartenSource(bundleID: String?, appName: String?) -> Bool {
        SourceAppIdentity.isMartenSource(bundleID: bundleID, appName: appName)
    }
}

final class AppIconLoader: ObservableObject {
    @Published private(set) var icon: NSImage?

    private var loadTask: Task<Void, Never>?

    func load(bundleID: String?, appName: String? = nil, iconData: Data? = nil) {
        loadTask?.cancel()
        icon = nil

        let resolvedBundleID = SourceAppIdentityResolver.resolvedBundleID(
            bundleID: bundleID,
            appName: appName
        )
        if let resolvedBundleID,
           resolvedBundleID.isMartenBundleIdentifier,
           let martenIcon = NSApplication.shared.applicationIconImage
           ?? NSImage(named: NSImage.applicationIconName) {
            AppIconCache.shared.setIcon(martenIcon, bundleID: resolvedBundleID)
            icon = martenIcon
            return
        }

        if let iconData,
           !iconData.isEmpty,
           let embeddedIcon = NSImage(data: iconData) {
            if let resolvedBundleID {
                AppIconCache.shared.setIcon(embeddedIcon, bundleID: resolvedBundleID)
            }
            icon = embeddedIcon
            return
        }

        guard let resolvedBundleID else { return }

        if let cached = AppIconCache.shared.cachedIcon(bundleID: resolvedBundleID) {
            icon = cached
            return
        }
        if AppIconCache.shared.hasMissing(bundleID: resolvedBundleID) {
            return
        }

        loadTask = Task.detached { [weak self] in
            guard let self else { return }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedBundleID)
            else {
                AppIconCache.shared.setMissing(bundleID: resolvedBundleID)
                return
            }
            let loaded = NSWorkspace.shared.icon(forFile: url.path)
            AppIconCache.shared.setIcon(loaded, bundleID: resolvedBundleID)
            await MainActor.run {
                self.icon = loaded
            }
        }
    }
}

final class AppIconColorLoader: ObservableObject {
    @Published private(set) var color: NSColor?

    private var loadTask: Task<Void, Never>?

    func load(bundleID: String?, appName: String? = nil) {
        loadTask?.cancel()
        color = nil

        guard let resolvedBundleID = SourceAppIdentityResolver.resolvedBundleID(
            bundleID: bundleID,
            appName: appName
        ) else {
            return
        }

        if let preferredColor = AppIconCache.preferredColor(for: resolvedBundleID) {
            AppIconCache.shared.setColor(preferredColor, bundleID: resolvedBundleID)
            color = preferredColor
            return
        }
        if let cached = AppIconCache.shared.cachedColor(bundleID: resolvedBundleID) {
            color = cached
            return
        }
        if AppIconCache.shared.hasMissingColor(bundleID: resolvedBundleID) {
            return
        }

        loadTask = Task.detached { [weak self] in
            guard let self else { return }
            let icon: NSImage
            if let cachedIcon = AppIconCache.shared.cachedIcon(bundleID: resolvedBundleID) {
                icon = cachedIcon
            } else {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedBundleID)
                else {
                    AppIconCache.shared.setMissingColor(bundleID: resolvedBundleID)
                    return
                }
                let loaded = NSWorkspace.shared.icon(forFile: url.path)
                AppIconCache.shared.setIcon(loaded, bundleID: resolvedBundleID)
                icon = loaded
            }

            guard let average = icon.averageColor() else {
                AppIconCache.shared.setMissingColor(bundleID: resolvedBundleID)
                return
            }
            let boosted = average.boostedForHeader() ?? average
            AppIconCache.shared.setColor(boosted, bundleID: resolvedBundleID)
            await MainActor.run {
                self.color = boosted
            }
        }
    }
}

struct AppIconView: View {
    let bundleID: String?
    let appName: String?
    let iconData: Data?
    let size: CGFloat

    @StateObject private var loader = AppIconLoader()

    init(bundleID: String?, appName: String? = nil, iconData: Data? = nil, size: CGFloat = 16) {
        self.bundleID = bundleID
        self.appName = appName
        self.iconData = iconData
        self.size = size
    }

    var body: some View {
        Group {
            if let icon = loader.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if SourceAppIdentityResolver.isMartenSource(bundleID: bundleID, appName: appName) {
                if let martenIcon = NSApplication.shared.applicationIconImage
                    ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: martenIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: max(10, size - 4), weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "app")
                    .font(.system(size: max(10, size - 4), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loader.load(bundleID: bundleID, appName: appName, iconData: iconData)
        }
        .onChange(of: sourceIdentitySignature) { _, _ in
            loader.load(bundleID: bundleID, appName: appName, iconData: iconData)
        }
    }

    private var sourceIdentitySignature: SourceIdentitySignature {
        SourceIdentitySignature(
            bundleID: bundleID ?? "",
            appName: appName ?? "",
            iconByteCount: iconData?.count ?? 0
        )
    }

    private struct SourceIdentitySignature: Equatable {
        let bundleID: String
        let appName: String
        let iconByteCount: Int
    }
}

extension NSImage {
    private static let averageColorContext = CIContext(options: [.workingColorSpace: NSNull()])

    func averageColor() -> NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        guard
            let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: ciImage,
                    kCIInputExtentKey: CIVector(cgRect: extent)
                ]
            ),
            let outputImage = filter.outputImage
        else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        Self.averageColorContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let alpha = CGFloat(bitmap[3]) / 255.0
        guard alpha > 0.05 else { return nil }

        return NSColor(
            srgbRed: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: 1.0
        )
    }
}

extension NSColor {
    func boostedForHeader() -> NSColor? {
        guard let srgb = usingColorSpace(.sRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Very low-saturation icons often average to gray; anchor hue from the dominant channel.
        if saturation < 0.14 {
            hue = srgb.dominantChannelHue
        }

        let boostedSaturation = min(1.0, max(0.88, saturation * 2.2 + 0.18))
        let boostedBrightness = min(1.0, max(0.9, brightness * 1.35 + 0.15))
        return NSColor(
            hue: hue,
            saturation: boostedSaturation,
            brightness: boostedBrightness,
            alpha: 1.0
        )
    }

    private var dominantChannelHue: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        if red >= green, red >= blue {
            return 0.02
        }
        if green >= red, green >= blue {
            return 0.34
        }
        return 0.59
    }
}

extension String {
    var isMartenBundleIdentifier: Bool {
        SourceAppIdentity.isMartenBundleID(self)
    }
}
