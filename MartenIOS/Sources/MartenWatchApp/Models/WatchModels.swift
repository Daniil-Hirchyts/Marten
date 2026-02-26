import Foundation
import MartenCore

struct WatchPinboardSummary: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
    let iconName: String?
    let isSystemMarten: Bool
    let isShared: Bool
    let canMakeChanges: Bool
}

struct WatchClipSummary: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let createdAt: Date
    let modifiedAt: Date
    let itemType: ItemType
    let primaryText: String?
    let plainText: String?
    let sourceAppName: String?
    let pinboardIDs: [UUID]
    let isPinned: Bool
    let byteCount: Int64
    let thumbnailPath: String?

    var colorHex: String? {
        guard itemType == .color, let text = primaryText else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Accept #-prefixed or raw hex strings of 6 or 8 chars
        var cleaned = trimmed
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8,
              cleaned.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return "#\(cleaned)"
    }

    var preferredText: String {
        let plain = plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !plain.isEmpty {
            return plain
        }

        let primary = primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty {
            return primary
        }

        return fallbackTitle
    }

    var title: String {
        let text = preferredText
        return text.isEmpty ? fallbackTitle : text
    }

    var subtitle: String {
        switch itemType {
        case .text, .richText, .code:
            return preferredText
        case .url:
            return primaryText ?? "URL"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .color:
            return primaryText ?? "Color"
        case .mixed:
            return "Mixed Content"
        }
    }

    var displayTypeTitle: String {
        switch itemType {
        case .text, .richText:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "Link"
        case .code:
            return "Code"
        case .color:
            return "Color"
        case .mixed:
            return "Item"
        }
    }

    var systemImageName: String {
        switch itemType {
        case .text, .richText:
            return "doc.text"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .url:
            return "link"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .color:
            return "paintpalette"
        case .mixed:
            return "square.stack.3d.up"
        }
    }

    private var fallbackTitle: String {
        switch itemType {
        case .text, .richText:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "URL"
        case .code:
            return "Code"
        case .color:
            return "Color"
        case .mixed:
            return "Item"
        }
    }
}
