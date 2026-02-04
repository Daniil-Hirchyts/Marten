import ClipboardCore
import Foundation

final class ItemTypeClassifier {
    func classify(
        representations: [ClipRepresentationPayload],
        primaryText: String?,
        textLooksLikeCode: Bool
    ) -> ItemType {
        var itemType = deriveItemType(from: representations, primaryText: primaryText)
        if textLooksLikeCode, itemType == .text {
            itemType = .code
        }
        return itemType
    }

    private func deriveItemType(
        from representations: [ClipRepresentationPayload],
        primaryText: String?
    ) -> ItemType {
        var hasText = false
        var hasRichText = false
        var hasImage = false
        var hasFile = false
        var hasURL = false

        for rep in representations {
            switch rep.kind {
            case .plainText, .markdown:
                hasText = true
            case .rtf, .html:
                hasRichText = true
            case .png, .jpeg, .tiff, .pdf:
                hasImage = true
            case .fileURL:
                hasFile = true
            case .url:
                hasURL = true
            case .custom:
                break
            }
        }

        if hasFile, let text = primaryText {
            let imageExtensions = [
                "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "heif", "webp", "svg",
                "ico",
            ]
            let url = URL(fileURLWithPath: text)
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                return .image
            }
        }

        if hasFile { return .file }
        if hasImage { return .image }
        if hasURL { return .url }
        if hasRichText { return .richText }
        if hasText {
            if let primaryText, isHexColor(primaryText) {
                return .color
            }
            return .text
        }

        return .mixed
    }

    private func isHexColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var s = trimmed
        if s.lowercased().hasPrefix("0x") {
            s = String(s.dropFirst(2))
        }
        if s.hasPrefix("#") {
            s = String(s.dropFirst())
        }
        let cleaned = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count == 3 || cleaned.count == 6 || cleaned.count == 8 {
            return cleaned.allSatisfy { $0.isHexDigit }
        }
        return false
    }
}

