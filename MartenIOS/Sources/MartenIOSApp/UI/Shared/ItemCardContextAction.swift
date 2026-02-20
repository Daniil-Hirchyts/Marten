public enum ItemCardContextAction: String, CaseIterable, Sendable {
    case copy
    case copyPlainText
    case preview
    case togglePin
    case share
    case moveToPinboard
    case delete

    public static let ordered: [ItemCardContextAction] = [
        .copy,
        .copyPlainText,
        .preview,
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
                .togglePin,
                .share,
                .moveToPinboard,
                .delete,
            ]
        }
        return ordered
    }

    public var title: String {
        switch self {
        case .copy:
            return "Copy"
        case .copyPlainText:
            return "Copy as Plain Text"
        case .preview:
            return "Preview"
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
}
