import AppKit
import ClipboardCore

/// Builds `NSPasteboardItem` instances from `ClipItem` data.
///
/// Shared by `PasteEngine` (for clipboard write + paste) and `NativeDragSource`
/// (for native drag-and-drop to external apps).
public final class PasteboardItemBuilder {
    private let assetStore: AssetStore

    public init(assetStore: AssetStore = .shared) {
        self.assetStore = assetStore
    }

    /// Build an `NSPasteboardItem` preserving all original representations.
    public func buildPasteboardItem(from item: ClipItem) throws -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        let sorted = item.representations?.sorted { $0.displayOrder < $1.displayOrder } ?? []
        for rep in sorted {
            try addRepresentation(rep, to: pasteboardItem)
        }
        return pasteboardItem
    }

    /// Build a plain-text-only `NSPasteboardItem`.
    public func buildPlainTextPasteboardItem(from item: ClipItem) -> NSPasteboardItem? {
        guard let plainText = item.plainTextContent, !plainText.isEmpty else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(plainText, forType: .string)
        return pasteboardItem
    }

    // MARK: - Private

    private func addRepresentation(
        _ representation: ClipRepresentation, to pasteboardItem: NSPasteboardItem
    ) throws {
        let type = NSPasteboard.PasteboardType(representation.uti)
        let kind = representation.kindValue

        if (kind == .rtf || kind == .html),
            let richTextData = try sanitizedRichTextData(for: representation),
            let attributed = NSAttributedString.clipboardAttributedString(
                from: richTextData,
                kind: kind
            )
        {
            pasteboardItem.setData(richTextData, forType: type)
            pasteboardItem.setString(attributed.string, forType: .string)
            return
        }

        if let textData = representation.textData,
            let text = String(data: textData, encoding: .utf8)
        {
            switch kind {
            case .fileURL:
                let url = URL(fileURLWithPath: text)
                pasteboardItem.setString(url.absoluteString, forType: type)
                return
            case .url:
                pasteboardItem.setString(text, forType: type)
                return
            case .plainText:
                pasteboardItem.setString(text, forType: .string)
                pasteboardItem.setString(text, forType: type)
                return
            default:
                break
            }
        }

        if let data = try representationData(for: representation) {
            pasteboardItem.setData(data, forType: type)
            return
        }
    }

    private func sanitizedRichTextData(for representation: ClipRepresentation) throws -> Data? {
        let kind = representation.kindValue
        guard kind == .rtf || kind == .html else { return nil }
        guard
            let data = try representationData(for: representation),
            let attributed = NSAttributedString.clipboardAttributedString(from: data, kind: kind)
        else {
            return nil
        }

        return attributed
            .removingTextColorAttributes()
            .clipboardData(for: kind)
    }

    private func representationData(for representation: ClipRepresentation) throws -> Data? {
        if let data = representation.binaryData {
            return data
        }

        if let data = representation.textData {
            return data
        }

        if let assetRef = representation.assetRef {
            return try assetStore.load(
                assetRef: assetRef, fileExtension: representation.fileExtension)
        }

        return nil
    }
}
