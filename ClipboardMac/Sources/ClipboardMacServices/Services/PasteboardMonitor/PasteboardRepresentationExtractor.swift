import AppKit
import ClipboardCore

public struct PasteboardExtraction {
    public let representations: [ClipRepresentationPayload]
    public let primaryText: String?
    public let needsLinkPreview: Bool
    public let textLooksLikeCode: Bool
    public let typesForFiltering: [String]
    public let dataSize: Int

    public init(
        representations: [ClipRepresentationPayload],
        primaryText: String?,
        needsLinkPreview: Bool,
        textLooksLikeCode: Bool,
        typesForFiltering: [String],
        dataSize: Int
    ) {
        self.representations = representations
        self.primaryText = primaryText
        self.needsLinkPreview = needsLinkPreview
        self.textLooksLikeCode = textLooksLikeCode
        self.typesForFiltering = typesForFiltering
        self.dataSize = dataSize
    }
}

public final class PasteboardRepresentationExtractor {
    public static let defaultExtractors: [any PasteboardTypeExtractor] = [
        StringExtractor(),
        RTFExtractor(),
        HTMLExtractor(),
        URLExtractor(),
        ImageExtractor(),
    ]

    private let settings: any CaptureSettingsProviding
    private let extractors: [any PasteboardTypeExtractor]

    public init(
        settings: any CaptureSettingsProviding = UserDefaultsCaptureSettingsProvider(),
        extractors: [any PasteboardTypeExtractor] = PasteboardRepresentationExtractor.defaultExtractors
    ) {
        self.settings = settings
        self.extractors = extractors
    }

    public func extract(from pasteboard: NSPasteboard) -> PasteboardExtraction? {
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

        let pasteboardTypes = pasteboard.types?.map { $0.rawValue } ?? []
        let promisedTypes = pasteboardTypes.filter {
            $0 == "com.apple.pasteboard.promised-file-url"
                || $0 == "com.apple.pasteboard.promised-file-content-type"
        }

        var typesForFiltering = representations.map { $0.uti }
        typesForFiltering.append(contentsOf: promisedTypes)
        let dataSize = representations.compactMap { $0.data?.count }.reduce(0, +)

        return PasteboardExtraction(
            representations: representations,
            primaryText: primaryText,
            needsLinkPreview: needsLinkPreview,
            textLooksLikeCode: textLooksLikeCode,
            typesForFiltering: typesForFiltering,
            dataSize: dataSize
        )
    }
}
