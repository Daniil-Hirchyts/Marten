import SwiftUI

struct ColorPreview: View {
    let hex: String

    var body: some View {
        let normalized = normalize(hex)
        let background = normalized.map { Color(hex: $0, fallback: .gray) } ?? .gray
        let foreground = normalized.map(foregroundColor) ?? .white

        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
            Text(normalized ?? hex)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
        }
    }

    private func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var s = trimmed
        if s.lowercased().hasPrefix("0x") {
            s = String(s.dropFirst(2))
        }
        if s.hasPrefix("#") {
            s = String(s.dropFirst())
        }
        let cleaned = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count == 3 {
            let chars = Array(cleaned)
            return
                "#\(String(repeating: String(chars[0]), count: 2))\(String(repeating: String(chars[1]), count: 2))\(String(repeating: String(chars[2]), count: 2))"
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

    private func foregroundColor(_ normalizedHex: String) -> Color {
        let cleaned = normalizedHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return .white
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }
}
