import AppKit
import CoreImage
import Foundation
import SwiftUI

final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let colorCache = NSCache<NSString, NSColor>()
    private var missingBundleIDs: Set<String> = []
    private var missingColorBundleIDs: Set<String> = []
    private let lock = NSLock()

    func cachedIcon(bundleID: String) -> NSImage? {
        cache.object(forKey: bundleID as NSString)
    }

    func cachedColor(bundleID: String) -> NSColor? {
        colorCache.object(forKey: bundleID as NSString)
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

final class AppIconColorLoader: ObservableObject {
    @Published private(set) var color: NSColor?

    private var loadTask: Task<Void, Never>?

    func load(bundleID: String?) {
        loadTask?.cancel()
        color = nil

        guard let bundleID, !bundleID.isEmpty else { return }
        if let cached = AppIconCache.shared.cachedColor(bundleID: bundleID) {
            color = cached
            return
        }
        if AppIconCache.shared.hasMissingColor(bundleID: bundleID) {
            return
        }

        loadTask = Task.detached { [weak self] in
            guard let self else { return }
            let icon: NSImage
            if let cachedIcon = AppIconCache.shared.cachedIcon(bundleID: bundleID) {
                icon = cachedIcon
            } else {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                else {
                    AppIconCache.shared.setMissingColor(bundleID: bundleID)
                    return
                }
                let loaded = NSWorkspace.shared.icon(forFile: url.path)
                AppIconCache.shared.setIcon(loaded, bundleID: bundleID)
                icon = loaded
            }

            guard let average = icon.averageColor() else {
                AppIconCache.shared.setMissingColor(bundleID: bundleID)
                return
            }
            let boosted = average.boostedForHeader() ?? average
            AppIconCache.shared.setColor(boosted, bundleID: bundleID)
            await MainActor.run {
                self.color = boosted
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

        let boostedSaturation: CGFloat
        if saturation < 0.08 {
            boostedSaturation = 0.65
        } else if saturation < 0.25 {
            boostedSaturation = 0.9
        } else {
            boostedSaturation = min(0.95, max(0.9, saturation * 2.9))
        }
        let boostedBrightness = min(0.95, max(0.9, brightness * 1.85 + 0.12))
        return NSColor(
            hue: hue,
            saturation: boostedSaturation,
            brightness: boostedBrightness,
            alpha: 1.0
        )
    }
}
