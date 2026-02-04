import AppKit
import ClipboardCore
import Foundation
import OSLog
import UniformTypeIdentifiers

public final class PasteboardExtractor {
    private static let logger = Logger(subsystem: "com.paste.clipboard", category: "extractor")

    private let representationExtractor: PasteboardRepresentationExtractor
    private let contentFilter: ClipboardContentFilter
    private let itemTypeClassifier: ItemTypeClassifier

    public init(settings: any CaptureSettingsProviding = UserDefaultsCaptureSettingsProvider()) {
        self.representationExtractor = PasteboardRepresentationExtractor(settings: settings)
        self.contentFilter = ClipboardContentFilter(settings: settings)
        self.itemTypeClassifier = ItemTypeClassifier()
    }

    public func extract(from pasteboard: NSPasteboard) -> ClipItemPayload? {
        guard let extraction = representationExtractor.extract(from: pasteboard) else {
            return nil
        }

        let filterResult = contentFilter.evaluate(
            text: extraction.primaryText,
            types: extraction.typesForFiltering,
            dataSize: extraction.dataSize
        )
        if filterResult.shouldFilter, let reason = filterResult.reason {
            Self.logger.info("Filtered clipboard content: \(reason, privacy: .public)")
            return nil
        }

        let itemType = itemTypeClassifier.classify(
            representations: extraction.representations,
            primaryText: extraction.primaryText,
            textLooksLikeCode: extraction.textLooksLikeCode
        )
        return ClipItemPayload(
            representations: extraction.representations,
            primaryText: extraction.primaryText,
            itemType: itemType,
            needsLinkPreview: extraction.needsLinkPreview,
            isSensitive: filterResult.isSensitive,
            isTransient: filterResult.isTransient
        )
    }
}
