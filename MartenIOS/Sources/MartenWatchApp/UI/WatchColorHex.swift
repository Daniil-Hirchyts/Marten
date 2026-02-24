import SwiftUI

extension Color {
    static func watchColor(hex: String, fallback: Color = .accentColor) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        guard let value = UInt64(cleaned, radix: 16) else {
            return fallback
        }

        switch cleaned.count {
        case 6:
            let red = Double((value >> 16) & 0xFF) / 255
            let green = Double((value >> 8) & 0xFF) / 255
            let blue = Double(value & 0xFF) / 255
            return Color(red: red, green: green, blue: blue)
        case 8:
            let alpha = Double((value >> 24) & 0xFF) / 255
            let red = Double((value >> 16) & 0xFF) / 255
            let green = Double((value >> 8) & 0xFF) / 255
            let blue = Double(value & 0xFF) / 255
            return Color(red: red, green: green, blue: blue, opacity: alpha)
        default:
            return fallback
        }
    }
}
