import AppKit
import ClipboardCore
import Foundation
import UniformTypeIdentifiers

public final class PasteboardExtractor {
    private let extractors: [PasteboardTypeExtractor] = [
        StringExtractor(),
        RTFExtractor(),
        HTMLExtractor(),
        URLExtractor(),
        ImageExtractor()
    ]
    
    public init() {}

    public func extract(from pasteboard: NSPasteboard) -> ClipItemPayload? {
        var representations: [ClipRepresentationPayload] = []
        var primaryText: String?
        var needsLinkPreview = false
        var textLooksLikeCode = false

        for extractor in extractors {
            if let result = extractor.extract(from: pasteboard, displayOrder: Int16(representations.count)) {
                representations.append(result.representation)
                if primaryText == nil {
                    primaryText = result.primaryText
                }
                needsLinkPreview = needsLinkPreview || result.needsLinkPreview
                textLooksLikeCode = textLooksLikeCode || result.textLooksLikeCode
            }
        }

        guard !representations.isEmpty else {
            return nil
        }

        var itemType = deriveItemType(from: representations)
        if textLooksLikeCode && itemType == .text {
            itemType = .code
        }
        return ClipItemPayload(
            representations: representations,
            primaryText: primaryText,
            itemType: itemType,
            needsLinkPreview: needsLinkPreview
        )
    }

    private func deriveItemType(from representations: [ClipRepresentationPayload]) -> ItemType {
        enum Category: Hashable {
            case text
            case richText
            case image
            case file
            case url
        }

        var categories = Set<Category>()
        for rep in representations {
            switch rep.kind {
            case .plainText, .markdown:
                categories.insert(.text)
            case .rtf, .html:
                categories.insert(.richText)
            case .png, .jpeg, .tiff, .pdf:
                categories.insert(.image)
            case .fileURL:
                categories.insert(.file)
            case .url:
                categories.insert(.url)
            case .custom:
                break
            }
        }

        if categories.count == 2, categories.contains(.richText), categories.contains(.text) {
            return .richText
        }

        guard categories.count == 1, let category = categories.first else {
            return categories.isEmpty ? .text : .mixed
        }

        switch category {
        case .text:
            return .text
        case .richText:
            return .richText
        case .image:
            return .image
        case .file:
            return .file
        case .url:
            return .url
        }
    }
}
