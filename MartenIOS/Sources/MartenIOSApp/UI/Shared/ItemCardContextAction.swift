import Foundation
import MartenCore

public enum ItemCardContextAction: String, CaseIterable, Sendable {
    case copy
    case copyPlainText
    case preview
    case edit
    case convertType
    case togglePin
    case share
    case moveToPinboard
    case delete

    private static let convertibleTypes: [ItemType] = [
        .text,
        .url,
        .code,
        .color,
    ]

    public static let ordered: [ItemCardContextAction] = [
        .copy,
        .copyPlainText,
        .preview,
        .edit,
        .convertType,
        .share,
        .moveToPinboard,
        .delete,
    ]

    public static func ordered(allowPinning: Bool) -> [ItemCardContextAction] {
        if allowPinning {
            return [
                .copy,
                .copyPlainText,
                .preview,
                .edit,
                .convertType,
                .togglePin,
                .share,
                .moveToPinboard,
                .delete,
            ]
        }
        return ordered
    }

    public static func conversionTargets(for currentType: ItemType, sourceText: String?) -> [ItemType] {
        guard convertibleTypes.contains(currentType) else { return [] }

        let normalizedText = sourceText?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return convertibleTypes.compactMap { candidate in
            guard candidate != currentType else { return nil }

            if candidate == .url, !hasConvertibleURL(in: normalizedText) {
                return nil
            }

            if candidate == .color, !hasConvertibleColor(in: normalizedText) {
                return nil
            }

            return candidate
        }
    }

    public static func conversionTypeSystemImage(_ type: ItemType) -> String {
        switch type {
        case .text:
            return "doc.plaintext"
        case .richText:
            return "doc.plaintext"
        case .url:
            return "link"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .color:
            return "paintpalette"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .mixed:
            return "square.stack.3d.up"
        }
    }

    public var title: String {
        switch self {
        case .copy:
            return "Copy"
        case .copyPlainText:
            return "Copy as Plain Text"
        case .preview:
            return "Preview"
        case .edit:
            return "Edit"
        case .convertType:
            return "Convert Type"
        case .togglePin:
            return "Pin"
        case .share:
            return "Share"
        case .moveToPinboard:
            return "Move to Pinboard"
        case .delete:
            return "Delete"
        }
    }

    public var systemImage: String {
        switch self {
        case .copy:
            return "doc.on.doc"
        case .copyPlainText:
            return "textformat"
        case .preview:
            return "eye"
        case .edit:
            return "pencil"
        case .convertType:
            return "arrow.triangle.2.circlepath"
        case .togglePin:
            return "pin"
        case .share:
            return "square.and.arrow.up"
        case .moveToPinboard:
            return "circle.dashed"
        case .delete:
            return "trash"
        }
    }

    public var isDestructive: Bool {
        self == .delete
    }

    private static func hasConvertibleColor(in text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return ColorHex.normalizedHex(from: text) != nil
    }

    private static func hasConvertibleURL(in text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if linkDetector?.firstMatch(in: text, options: [], range: fullRange) != nil {
            return true
        }

        guard !text.contains(where: \.isWhitespace) else { return false }

        if let directURL = URL(string: text),
           directURL.scheme != nil,
           directURL.host != nil {
            return true
        }

        guard text.contains(".") || text.lowercased().hasPrefix("localhost") else {
            return false
        }

        let prefixedText = "https://\(text)"
        guard let normalizedURL = URL(string: prefixedText), normalizedURL.host != nil else {
            return false
        }

        return true
    }
}
