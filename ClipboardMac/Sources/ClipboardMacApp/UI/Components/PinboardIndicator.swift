import AppKit
import SwiftUI

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
        NSImage(systemSymbolName: token, accessibilityDescription: nil) != nil
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
                .shadow(color: signShadowColor, radius: signShadowRadius, x: 0, y: 0.45)
        case .text(let token):
            Text(token)
                .font(.system(size: size * 0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: signShadowColor, radius: signShadowRadius, x: 0, y: 0.45)
        }
    }

    private var isDarkBackground: Bool {
        let color = NSColor(hex: colorHex).usingColorSpace(.sRGB) ?? NSColor(hex: colorHex)
        let luminance = (0.2126 * color.redComponent) + (0.7152 * color.greenComponent)
            + (0.0722 * color.blueComponent)
        return luminance < 0.56
    }
}
