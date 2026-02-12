import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PinboardSignKind: Equatable {
    case symbol(String)
    case text(String)
}

enum PinboardSignResolver {
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolve(_ raw: String?) -> PinboardSignKind? {
        guard let token = normalize(raw) else { return nil }
        return isSystemSymbol(token) ? .symbol(token) : .text(token)
    }

    static func isSystemSymbol(_ token: String) -> Bool {
        #if canImport(UIKit)
        UIImage(systemName: token) != nil
        #elseif canImport(AppKit)
        NSImage(systemSymbolName: token, accessibilityDescription: nil) != nil
        #else
        false
        #endif
    }
}

struct PinboardIndicator: View {
    let colorHex: String
    var sign: String? = nil
    var size: CGFloat = 12
    var isAssigned: Bool = true
    var showBorder: Bool = true

    private var baseColor: Color {
        Color(hex: colorHex, fallback: .gray)
    }

    private var signColor: Color {
        isDarkBackground ? .white.opacity(0.95) : .black.opacity(0.78)
    }

    private var signShadowColor: Color {
        .black.opacity(isDarkBackground ? 0.22 : 0.28)
    }

    private var signShadowRadius: CGFloat {
        max(0.6, size * 0.11)
    }

    private var fillOpacity: CGFloat {
        isAssigned ? 1.0 : 0.26
    }

    private var signContainerSize: CGFloat {
        max(6, size * 0.72)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(baseColor.opacity(fillOpacity))

            if showBorder {
                Circle()
                    .strokeBorder(baseColor.opacity(0.96), lineWidth: max(1, size * 0.09))
            }

            if let signKind = PinboardSignResolver.resolve(sign) {
                signView(signKind)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func signView(_ sign: PinboardSignKind) -> some View {
        switch sign {
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(signColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: signContainerSize, height: signContainerSize, alignment: .center)
                .offset(y: size * 0.015)
                .shadow(color: signShadowColor, radius: signShadowRadius, x: 0, y: 0.45)
        case .text(let token):
            Text(token)
                .font(.system(size: size * 0.56))
                .foregroundStyle(signColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: signContainerSize, height: signContainerSize, alignment: .center)
                .offset(y: textSignVerticalOffset(for: token))
                .shadow(color: signShadowColor, radius: signShadowRadius, x: 0, y: 0.45)
        }
    }

    private func textSignVerticalOffset(for token: String) -> CGFloat {
        token.containsEmojiGlyph ? size * 0.035 : size * 0.015
    }

    private var isDarkBackground: Bool {
        let rgb = HexColorParser.rgbComponents(from: colorHex)
        let red = rgb.red
        let green = rgb.green
        let blue = rgb.blue
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance < 0.56
    }
}

private enum HexColorParser {
    static func rgbComponents(from hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")

        if sanitized.count == 3 {
            sanitized = sanitized.map { "\($0)\($0)" }.joined()
        }

        guard sanitized.count == 6 else {
            return (0.5, 0.5, 0.5)
        }

        var rgb: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&rgb) else {
            return (0.5, 0.5, 0.5)
        }

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        return (red, green, blue)
    }
}

private extension String {
    var containsEmojiGlyph: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}
