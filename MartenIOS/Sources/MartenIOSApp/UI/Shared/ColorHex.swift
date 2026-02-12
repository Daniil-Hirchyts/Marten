import Foundation
import SwiftUI

public struct PinboardColorOption: Hashable {
    public let name: String
    public let hex: String

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

public enum PinboardColorPalette {
    public static let all: [PinboardColorOption] = [
        PinboardColorOption(name: "Blue", hex: "#4A95FF"),
        PinboardColorOption(name: "Indigo", hex: "#5A67D8"),
        PinboardColorOption(name: "Violet", hex: "#7C4DFF"),
        PinboardColorOption(name: "Purple", hex: "#8338EC"),
        PinboardColorOption(name: "Pink", hex: "#FF006E"),
        PinboardColorOption(name: "Rose", hex: "#FF4D9D"),
        PinboardColorOption(name: "Red", hex: "#E63946"),
        PinboardColorOption(name: "Coral", hex: "#FF7F50"),
        PinboardColorOption(name: "Orange", hex: "#FB5607"),
        PinboardColorOption(name: "Amber", hex: "#FF9F1C"),
        PinboardColorOption(name: "Yellow", hex: "#FFBE0B"),
        PinboardColorOption(name: "Lime", hex: "#9BC53D"),
        PinboardColorOption(name: "Green", hex: "#2A9D8F"),
        PinboardColorOption(name: "Teal", hex: "#00BFA6"),
        PinboardColorOption(name: "Cyan", hex: "#48CAE4"),
        PinboardColorOption(name: "Slate", hex: "#6C757D"),
    ]

    public static let defaultHex = all.first?.hex ?? "#4A95FF"
}

public enum ColorHex {
    public static func normalizedHex(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if candidate.lowercased().hasPrefix("0x") {
            candidate = String(candidate.dropFirst(2))
        }
        if candidate.hasPrefix("#") {
            candidate = String(candidate.dropFirst())
        }

        let cleaned = candidate.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count == 3 {
            let chars = Array(cleaned)
            return "#\(String(repeating: String(chars[0]), count: 2))\(String(repeating: String(chars[1]), count: 2))\(String(repeating: String(chars[2]), count: 2))"
                .uppercased()
        }

        if cleaned.count == 6 {
            return "#\(cleaned)".uppercased()
        }

        if cleaned.count == 8 {
            let start = cleaned.startIndex
            let end = cleaned.index(start, offsetBy: 6)
            return "#\(String(cleaned[start..<end]))".uppercased()
        }

        return nil
    }

    public static func foregroundColor(for normalizedHex: String) -> Color {
        let cleaned = normalizedHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return .white
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        return luminance > 0.6 ? .black : .white
    }
}

public extension Color {
    init(hex: String, fallback: Color = .gray) {
        guard let normalized = ColorHex.normalizedHex(from: hex) else {
            self = fallback
            return
        }

        let cleaned = normalized.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(cleaned, radix: 16) else {
            self = fallback
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
