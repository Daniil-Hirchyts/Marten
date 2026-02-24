import Foundation
import SwiftUI

public struct SourceAppIconDescriptor: Equatable {
    public enum Content: Equatable {
        case symbol(String)
        case monogram(String)
        case generic
    }

    public let content: Content
    public let backgroundHex: String

    public var backgroundColor: Color {
        Color(hex: backgroundHex, fallback: .gray)
    }

    public var foregroundColor: Color {
        let normalized = ColorHex.normalizedHex(from: backgroundHex) ?? "#808080"
        return ColorHex.foregroundColor(for: normalized)
    }

    public static func resolve(bundleID: String?, appName: String?) -> SourceAppIconDescriptor {
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

    public static func stableHash(forIdentifier identifier: String) -> String {
        let hash = fnv1aHash(identifier)
        return String(format: "%08X", hash)
    }

    public static func stableColorHex(forIdentifier identifier: String) -> String {
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

    public static func fnv1aHash(_ value: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in value.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return hash
    }

    public static func fnv1aHash(_ data: Data) -> UInt32 {
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
