import AppKit
import Foundation

public extension ClipItem {
    /// Rich text content (RTF preferred, HTML fallback) decoded from stored representations.
    var styledTextContent: NSAttributedString? {
        attributedTextContent(removingTextColors: false)
    }

    /// Rich text content with explicit color attributes removed.
    var styledTextContentWithoutTextColor: NSAttributedString? {
        attributedTextContent(removingTextColors: true)
    }

    private func attributedTextContent(removingTextColors: Bool) -> NSAttributedString? {
        let sortedRepresentations =
            representations?.sorted { $0.displayOrder < $1.displayOrder } ?? []

        if let attributed = decodeAttributedText(
            from: sortedRepresentations,
            kind: .rtf,
            removingTextColors: removingTextColors
        ) {
            return attributed
        }

        if let attributed = decodeAttributedText(
            from: sortedRepresentations,
            kind: .html,
            removingTextColors: removingTextColors
        ) {
            return attributed
        }

        return nil
    }

    private func decodeAttributedText(
        from representations: [ClipRepresentation],
        kind: RepresentationKind,
        removingTextColors: Bool
    ) -> NSAttributedString? {
        guard
            let representation = representations.first(where: { $0.kindValue == kind }),
            let data = representation.binaryData ?? representation.textData,
            let attributed = NSAttributedString.clipboardAttributedString(from: data, kind: kind)
        else {
            return nil
        }

        if removingTextColors {
            return attributed.removingTextColorAttributes()
        }
        return attributed
    }
}

public extension NSAttributedString {
    static func clipboardAttributedString(from data: Data, kind: RepresentationKind)
        -> NSAttributedString?
    {
        let options = readingOptions(for: kind)
        guard !options.isEmpty else { return nil }
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    func clipboardData(for kind: RepresentationKind) -> Data? {
        guard let documentType = documentType(for: kind) else { return nil }
        let range = NSRange(location: 0, length: length)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: documentType
        ]
        return try? data(from: range, documentAttributes: attributes)
    }

    func removingTextColorAttributes() -> NSAttributedString {
        guard length > 0 else { return self }

        let mutable = NSMutableAttributedString(attributedString: self)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let colorKeys: [NSAttributedString.Key] = [
            .foregroundColor,
            .backgroundColor,
            .strokeColor,
            .underlineColor,
            .strikethroughColor,
            .link,
        ]

        for key in colorKeys {
            mutable.removeAttribute(key, range: fullRange)
        }

        // Some imported rich text sources use nonstandard color keys
        // (for example CoreText keys). Strip any attribute whose key
        // name implies color or link styling.
        mutable.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            for key in attributes.keys where Self.isColorLikeAttributeKey(key) {
                mutable.removeAttribute(key, range: range)
            }
        }

        // Keep only supported style attributes so rendering never picks up
        // unsupported visual styling (especially custom color-like attributes).
        let normalized = NSMutableAttributedString(string: mutable.string)
        mutable.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            var supported: [NSAttributedString.Key: Any] = [:]
            for key in Self.supportedStyleKeys {
                if let value = attributes[key] {
                    supported[key] = value
                }
            }
            normalized.setAttributes(supported, range: range)
        }
        return normalized
    }

    private static func isColorLikeAttributeKey(_ key: NSAttributedString.Key) -> Bool {
        let raw = key.rawValue.lowercased()
        return raw.contains("color") || raw.contains("link")
    }

    private static let supportedStyleKeys: Set<NSAttributedString.Key> = [
        .font,
        .paragraphStyle,
        .underlineStyle,
        .strikethroughStyle,
        .kern,
        .ligature,
        .baselineOffset,
        .writingDirection,
        .verticalGlyphForm,
    ]

    private static func readingOptions(for kind: RepresentationKind)
        -> [NSAttributedString.DocumentReadingOptionKey: Any]
    {
        switch kind {
        case .rtf:
            return [.documentType: NSAttributedString.DocumentType.rtf]
        case .html:
            return [.documentType: NSAttributedString.DocumentType.html]
        default:
            return [:]
        }
    }

    private func documentType(for kind: RepresentationKind) -> NSAttributedString.DocumentType? {
        switch kind {
        case .rtf:
            return .rtf
        case .html:
            return .html
        default:
            return nil
        }
    }
}
