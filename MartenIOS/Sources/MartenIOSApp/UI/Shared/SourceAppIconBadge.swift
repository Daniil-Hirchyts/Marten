import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

struct SourceAppIconBadge: View {
    let bundleID: String?
    let appName: String?
    let iconData: Data?
    var size: CGFloat = 30

    @State private var remoteIcon: PlatformImage?

    private var descriptor: SourceAppIconDescriptor {
        SourceAppIconDescriptor.resolve(bundleID: bundleID, appName: appName)
    }

    private var normalizedBundleID: String? {
        guard let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return nil
        }
        return bundleID.lowercased()
    }

    private var embeddedIcon: PlatformImage? {
        guard let iconData, !iconData.isEmpty else { return nil }
        #if canImport(UIKit)
        return UIImage(data: iconData)
        #elseif canImport(AppKit)
        return NSImage(data: iconData)
        #endif
    }

    var body: some View {
        let bundleID = normalizedBundleID

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(descriptor.backgroundColor)

            if let embeddedIcon {
                remoteIconView(embeddedIcon)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else if let remoteIcon {
                remoteIconView(remoteIcon)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                content()
                    .foregroundStyle(descriptor.foregroundColor)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(descriptor.foregroundColor.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
        .task(id: taskID(bundleID: bundleID)) {
            remoteIcon = nil
            guard embeddedIcon == nil else { return }
            guard let bundleID else { return }
            let loadedIcon = await SourceAppIconRepository.shared.icon(forBundleID: bundleID)
            guard !Task.isCancelled else { return }
            remoteIcon = loadedIcon
        }
    }

    private func taskID(bundleID: String?) -> String {
        let digest = iconDataDigest(iconData)
        return "\(bundleID ?? "none")|\(digest)"
    }

    private func iconDataDigest(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "nil" }
        return String(format: "%08X", SourceAppIconDescriptor.fnv1aHash(data))
    }

    @ViewBuilder
    private func content() -> some View {
        switch descriptor.content {
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: size * 0.54, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .monogram(let token):
            Text(token)
                .font(.system(size: size * 0.42, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textCase(.uppercase)
        case .generic:
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private func remoteIconView(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
        #endif
    }
}

@MainActor
final class SourceAppIconRepository {
    static let shared = SourceAppIconRepository()

    #if canImport(UIKit)
    private let memoryCache = NSCache<NSString, UIImage>()
    #elseif canImport(AppKit)
    private let memoryCache = NSCache<NSString, NSImage>()
    #endif

    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    private let cacheDirectoryURL: URL?

    private init() {
        let fileManager = FileManager.default
        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = cachesDirectory.appendingPathComponent("MartenSourceAppIcons", isDirectory: true)
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            cacheDirectoryURL = directory
        } else {
            cacheDirectoryURL = nil
        }
    }

    func icon(forBundleID bundleID: String) async -> PlatformImage? {
        let key = bundleID.lowercased()

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let cached = loadFromDisk(bundleID: key) {
            memoryCache.setObject(cached, forKey: key as NSString)
            return cached
        }

        if let runningTask = inFlight[key] {
            return await runningTask.value
        }

        let task = Task<PlatformImage?, Never> {
            guard let artworkURL = await Self.lookupArtworkURL(bundleID: key),
                  let image = await Self.downloadImage(from: artworkURL) else {
                return nil
            }
            return image
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        guard let image else { return nil }
        memoryCache.setObject(image, forKey: key as NSString)
        saveToDisk(image: image, bundleID: key)
        return image
    }

    private func fileURL(for bundleID: String) -> URL? {
        guard let cacheDirectoryURL else { return nil }
        let hash = SourceAppIconDescriptor.stableHash(forIdentifier: bundleID)
        return cacheDirectoryURL
            .appendingPathComponent("app-icon-\(hash)")
            .appendingPathExtension("png")
    }

    private func loadFromDisk(bundleID: String) -> PlatformImage? {
        guard let fileURL = fileURL(for: bundleID),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }

    private func saveToDisk(image: PlatformImage, bundleID: String) {
        guard let fileURL = fileURL(for: bundleID),
              let data = encodedData(from: image) else {
            return
        }

        try? data.write(to: fileURL, options: [.atomic])
    }

    #if canImport(UIKit)
    private func encodedData(from image: UIImage) -> Data? {
        image.pngData()
    }
    #elseif canImport(AppKit)
    private func encodedData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
    #endif

    private struct AppStoreLookupResponse: Decodable {
        let results: [AppStoreLookupResult]
    }

    private struct AppStoreLookupResult: Decodable {
        let artworkUrl512: String?
        let artworkUrl100: String?
        let artworkUrl60: String?
        let artworkUrl30: String?
    }

    private static func lookupArtworkURL(bundleID: String) async -> URL? {
        for endpoint in lookupEndpoints(for: bundleID) {
            guard let data = await fetchData(from: endpoint),
                  let response = try? JSONDecoder().decode(AppStoreLookupResponse.self, from: data) else {
                continue
            }

            for result in response.results {
                for raw in [result.artworkUrl512, result.artworkUrl100, result.artworkUrl60, result.artworkUrl30] {
                    guard let raw else { continue }
                    if let url = normalizedArtworkURL(from: raw) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    private static func lookupEndpoints(for bundleID: String) -> [URL] {
        guard let escapedBundleID = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        let rawEndpoints = [
            "https://itunes.apple.com/lookup?bundleId=\(escapedBundleID)&entity=software",
            "https://itunes.apple.com/lookup?bundleId=\(escapedBundleID)&entity=macSoftware",
        ]

        return rawEndpoints.compactMap(URL.init(string:))
    }

    private static func normalizedArtworkURL(from raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        if components.scheme == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    private static func fetchData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        return data
    }

    private static func downloadImage(from url: URL) async -> PlatformImage? {
        guard let data = await fetchData(from: url) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
}

struct SourceAppIconDescriptor: Equatable {
    enum Content: Equatable {
        case symbol(String)
        case monogram(String)
        case generic
    }

    let content: Content
    let backgroundHex: String

    var backgroundColor: Color {
        Color(hex: backgroundHex, fallback: .gray)
    }

    var foregroundColor: Color {
        let normalized = ColorHex.normalizedHex(from: backgroundHex) ?? "#808080"
        return ColorHex.foregroundColor(for: normalized)
    }

    static func resolve(bundleID: String?, appName: String?) -> SourceAppIconDescriptor {
        let normalizedBundleID = normalize(bundleID)
        let normalizedAppName = normalize(appName)

        if let known = KnownAppSymbolMap.entry(
            for: normalizedBundleID,
            appName: normalizedAppName
        ) {
            return SourceAppIconDescriptor(
                content: .symbol(known.symbol),
                backgroundHex: known.backgroundHex
            )
        }

        if let monogram = monogram(forAppName: normalizedAppName, bundleID: normalizedBundleID) {
            let identity = normalizedBundleID ?? normalizedAppName ?? monogram
            return SourceAppIconDescriptor(
                content: .monogram(monogram),
                backgroundHex: stableColorHex(forIdentifier: identity)
            )
        }

        return SourceAppIconDescriptor(
            content: .generic,
            backgroundHex: "#6C757D"
        )
    }

    static func stableHash(forIdentifier identifier: String) -> String {
        let hash = fnv1aHash(identifier)
        return String(format: "%08X", hash)
    }

    static func stableColorHex(forIdentifier identifier: String) -> String {
        let hash = fnv1aHash(identifier)
        let hue = Double(hash % 360) / 360.0
        let saturation = 0.56 + Double((hash >> 8) % 24) / 100.0
        let brightness = 0.62 + Double((hash >> 16) % 24) / 100.0
        return hsvToHex(
            hue: hue,
            saturation: saturation,
            value: brightness
        )
    }

    static func fnv1aHash(_ value: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in value.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return hash
    }

    static func fnv1aHash(_ data: Data) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in data {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return hash
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func monogram(forAppName appName: String?, bundleID: String?) -> String? {
        if let appName {
            let fromName = monogramFromWords(appName)
            if let fromName, !fromName.isEmpty {
                return fromName
            }
        }

        guard let bundleID else { return nil }
        let suffix = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        let fromSuffix = monogramFromWords(suffix) ?? String(suffix.prefix(2))
        let sanitized = String(fromSuffix.filter { $0.isLetter || $0.isNumber })
        return sanitized.isEmpty ? nil : String(sanitized.prefix(2)).uppercased()
    }

    private static func monogramFromWords(_ raw: String) -> String? {
        let words = raw
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }

        if words.count >= 2 {
            guard let first = words[0].first, let second = words[1].first else { return nil }
            return "\(String(first))\(String(second))".uppercased()
        }

        guard let firstWord = words.first else { return nil }
        let scalars = firstWord.filter { $0.isLetter || $0.isNumber }
        guard !scalars.isEmpty else { return nil }
        return String(scalars.prefix(2)).uppercased()
    }

    private static func hsvToHex(hue: Double, saturation: Double, value: Double) -> String {
        let h = max(0.0, min(1.0, hue))
        let s = max(0.0, min(1.0, saturation))
        let v = max(0.0, min(1.0, value))

        let i = Int(floor(h * 6.0))
        let f = (h * 6.0) - Double(i)
        let p = v * (1.0 - s)
        let q = v * (1.0 - f * s)
        let t = v * (1.0 - (1.0 - f) * s)

        let rgb: (Double, Double, Double)
        switch i % 6 {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }

        let red = Int((rgb.0 * 255.0).rounded())
        let green = Int((rgb.1 * 255.0).rounded())
        let blue = Int((rgb.2 * 255.0).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum KnownAppSymbolMap {
    struct Entry: Equatable {
        let symbol: String
        let backgroundHex: String
    }

    private static let entries: [String: Entry] = [
        "com.apple.mobilesafari": Entry(symbol: "safari.fill", backgroundHex: "#0A84FF"),
        "com.apple.mobilemail": Entry(symbol: "envelope.fill", backgroundHex: "#007AFF"),
        "com.apple.mobilesms": Entry(symbol: "message.fill", backgroundHex: "#34C759"),
        "com.apple.mobilenotes": Entry(symbol: "note.text", backgroundHex: "#FFD60A"),
        "com.apple.documentsapp": Entry(symbol: "folder.fill", backgroundHex: "#4C9CFF"),
        "com.apple.mobileslideshow": Entry(symbol: "photo.on.rectangle.angled", backgroundHex: "#FF9500"),
        "com.apple.reminders": Entry(symbol: "checklist", backgroundHex: "#30D158"),
        "com.google.chrome.ios": Entry(symbol: "globe", backgroundHex: "#4285F4"),
        "org.mozilla.ios.firefox": Entry(symbol: "flame.fill", backgroundHex: "#FF7139"),
        "com.microsoft.office.outlook": Entry(symbol: "envelope.badge.fill", backgroundHex: "#0078D4"),
    ]

    private static let prefixEntries: [(prefix: String, entry: Entry)] = [
        ("com.apple.mobilesafari", Entry(symbol: "safari.fill", backgroundHex: "#0A84FF")),
        ("com.apple.mobilemail", Entry(symbol: "envelope.fill", backgroundHex: "#007AFF")),
        ("com.apple.mobilesms", Entry(symbol: "message.fill", backgroundHex: "#34C759")),
        ("com.apple.mobilenotes", Entry(symbol: "note.text", backgroundHex: "#FFD60A")),
        ("com.apple.documentsapp", Entry(symbol: "folder.fill", backgroundHex: "#4C9CFF")),
        ("com.apple.reminders", Entry(symbol: "checklist", backgroundHex: "#30D158")),
        ("com.apple.shortcuts", Entry(symbol: "square.stack.3d.forward.dottedline.fill", backgroundHex: "#00C7BE")),
        ("com.google.chrome", Entry(symbol: "globe", backgroundHex: "#4285F4")),
        ("org.mozilla.ios.firefox", Entry(symbol: "flame.fill", backgroundHex: "#FF7139")),
        ("com.microsoft.office.outlook", Entry(symbol: "envelope.badge.fill", backgroundHex: "#0078D4")),
        ("com.hirchyts.marten", Entry(symbol: "sparkles", backgroundHex: "#FF2E00")),
    ]

    private static let nameKeywordEntries: [(keyword: String, entry: Entry)] = [
        ("safari", Entry(symbol: "safari.fill", backgroundHex: "#0A84FF")),
        ("mail", Entry(symbol: "envelope.fill", backgroundHex: "#007AFF")),
        ("gmail", Entry(symbol: "envelope.fill", backgroundHex: "#EA4335")),
        ("messages", Entry(symbol: "message.fill", backgroundHex: "#34C759")),
        ("telegram", Entry(symbol: "paperplane.fill", backgroundHex: "#27A7E7")),
        ("whatsapp", Entry(symbol: "message.fill", backgroundHex: "#25D366")),
        ("discord", Entry(symbol: "gamecontroller.fill", backgroundHex: "#5865F2")),
        ("slack", Entry(symbol: "bubble.left.and.bubble.right.fill", backgroundHex: "#611F69")),
        ("instagram", Entry(symbol: "camera.fill", backgroundHex: "#E4405F")),
        ("youtube", Entry(symbol: "play.rectangle.fill", backgroundHex: "#FF0000")),
        ("x", Entry(symbol: "at", backgroundHex: "#111111")),
        ("twitter", Entry(symbol: "at", backgroundHex: "#1D9BF0")),
        ("reddit", Entry(symbol: "text.bubble.fill", backgroundHex: "#FF5700")),
        ("notion", Entry(symbol: "doc.text.fill", backgroundHex: "#111111")),
        ("marten", Entry(symbol: "sparkles", backgroundHex: "#FF2E00")),
        ("outlook", Entry(symbol: "envelope.badge.fill", backgroundHex: "#0078D4")),
        ("chrome", Entry(symbol: "globe", backgroundHex: "#4285F4")),
        ("firefox", Entry(symbol: "flame.fill", backgroundHex: "#FF7139")),
    ]

    static func entry(for bundleID: String?, appName: String?) -> Entry? {
        if let bundleID = bundleID?.lowercased() {
            if let exact = entries[bundleID] {
                return exact
            }

            if let prefixed = prefixEntries.first(where: { bundleID.hasPrefix($0.prefix) }) {
                return prefixed.entry
            }
        }

        if let appName = appName?.lowercased() {
            if let byName = nameKeywordEntries.first(where: { keywordMatch(name: appName, keyword: $0.keyword) }) {
                return byName.entry
            }
        }

        return nil
    }

    private static func keywordMatch(name: String, keyword: String) -> Bool {
        if keyword == "x" {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == "x"
        }

        return name.contains(keyword)
    }
}
