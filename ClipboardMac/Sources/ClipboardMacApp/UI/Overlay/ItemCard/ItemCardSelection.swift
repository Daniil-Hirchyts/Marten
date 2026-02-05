import AppKit
import ClipboardCore
import SwiftUI

extension ItemCard {
    var cardBackground: some View {
        cardShape
            .fill(
                colorItemBackground
                    ?? (colorScheme == .dark
                        ? Color(.sRGB, white: 0.04, opacity: 0.72)
                        : Color(.sRGB, white: 0.96, opacity: 0.9))
            )
    }

    var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Spacing.cardCornerRadius, style: .continuous)
    }

    @ViewBuilder
    var selectionBorder: some View {
        if isSelected {
            cardShape
                .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 4)
        }
    }

    var headerBackgroundShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: DesignTokens.Spacing.cardCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: DesignTokens.Spacing.cardCornerRadius
            ),
            style: .continuous
        )
    }

    var headerBackground: some View {
        headerBackgroundShape
            .inset(by: headerBackgroundInset)
            .fill(headerBackgroundColor)
    }

    var headerMinHeight: CGFloat {
        50
    }

    var headerBackgroundInset: CGFloat {
        0
    }

    var headerBackgroundColor: Color {
        if let pinboardColor = cached.primaryPinboardColor {
            return pinboardColor.opacity(0.9)
        }
        if let appColor = appColorLoader.color {
            return Color(nsColor: appColor).opacity(0.9)
        }
        return colorScheme == .dark
            ? Color(.sRGB, white: 0.2, opacity: 0.6)
            : Color(.sRGB, white: 0.85, opacity: 0.8)
    }

    var headerTextColor: Color {
        if cached.primaryPinboardColor != nil || appColorLoader.color != nil {
            return Color.white
        }
        return colorScheme == .dark ? Color.white : Color.black
    }

    var primaryTextColor: Color {
        if item.itemTypeValue == .color, let fg = colorItemForeground {
            return fg
        }
        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    var secondaryTextColor: Color {
        if item.itemTypeValue == .color, let fg = colorItemForeground {
            return fg.opacity(0.8)
        }
        return colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
    }

    var tertiaryTextColor: Color {
        if item.itemTypeValue == .color, let fg = colorItemForeground {
            return fg.opacity(0.7)
        }
        return colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    var headerSubtitle: String? {
        if let pinboardName = cached.primaryPinboardName {
            return pinboardName
        }
        return cached.sourceLabel
    }

    var isCompactSize: Bool {
        cardSize < 280
    }

    var cardPadding: CGFloat {
        isCompactSize ? 10 : 12
    }

    var titleFontSize: CGFloat {
        isCompactSize ? 13 : 14
    }

    var subtitleFontSize: CGFloat {
        isCompactSize ? 9 : 10
    }

    var contentFontSize: CGFloat {
        isCompactSize ? 11 : 12
    }

    var maxPreviewLines: Int {
        isCompactSize ? 3 : 5
    }

    var fileIconSize: CGFloat {
        if cardSize < 180 {
            return 30
        } else if cardSize < 220 {
            return 50
        } else if cardSize < 260 {
            return 80
        } else {
            return 120
        }
    }

    var shouldShowLeadingPreview: Bool {
        switch item.itemTypeValue {
        case .mixed:
            return true
        default:
            return false
        }
    }

    var colorFontSize: CGFloat {
        isCompactSize ? 18 : 24
    }

    var timeAgo: String {
        ItemCardFormatters.relativeDate.localizedString(for: item.modifiedAt, relativeTo: Date())
    }

    var accessibilityLabelText: String {
        if let customTitle = item.customTitle, !customTitle.isEmpty {
            return customTitle
        }
        if cached.shouldShowPrimaryTitle {
            return "\(cached.displayTitle), \(cached.primaryTitle)"
        }
        if let snippet = previewSnippet {
            return "\(cached.displayTitle), \(snippet)"
        }
        return cached.displayTitle
    }

    var accessibilityValueText: String {
        var parts: [String] = []
        parts.append(isSelected ? "Selected" : "Not selected")
        if item.isPinned {
            parts.append("Pinned")
        }
        parts.append(cached.statsLabel)
        return parts.joined(separator: ", ")
    }

    var previewSnippet: String? {
        guard let preview = cached.previewText else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "..."
        }
        return trimmed
    }
}

private enum ItemCardFormatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

enum ClipboardHexColor {
    static func normalizedHex(from text: String) -> String? {
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

    static func foregroundColor(forNormalizedHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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

private struct QuickPasteBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.blue.opacity(0.9))
            .clipShape(Circle())
    }
}
