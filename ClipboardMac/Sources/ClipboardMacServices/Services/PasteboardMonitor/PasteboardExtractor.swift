import AppKit
import ClipboardCore
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

public final class PasteboardExtractor {
    private static let logger = Logger(subsystem: "com.paste.clipboard", category: "extractor")

    private let extractors: [PasteboardTypeExtractor] = [
        StringExtractor(),
        RTFExtractor(),
        HTMLExtractor(),
        URLExtractor(),
        ImageExtractor(),
    ]

    private let confidentialClassifier = ConfidentialContentClassifier()
    private let transientClassifier = TransientContentClassifier()

    @AppStorage("ignoreConfidentialContent") private var ignoreConfidentialContent = true
    @AppStorage("ignoreTransientContent") private var ignoreTransientContent = true

    public init() {}

    public func extract(from pasteboard: NSPasteboard) -> ClipItemPayload? {
        var representations: [ClipRepresentationPayload] = []
        var primaryText: String?
        var needsLinkPreview = false
        var textLooksLikeCode = false

        let pasteboardTypes = pasteboard.types?.map { $0.rawValue } ?? []
        let promisedTypes = pasteboardTypes.filter {
            $0 == "com.apple.pasteboard.promised-file-url"
                || $0 == "com.apple.pasteboard.promised-file-content-type"
        }

        for extractor in extractors {
            if let result = extractor.extract(
                from: pasteboard, displayOrder: Int16(representations.count))
            {
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

        var typesForFiltering = representations.map { $0.uti }
        typesForFiltering.append(contentsOf: promisedTypes)
        let dataSize = representations.compactMap { $0.data?.count }.reduce(0, +)

        let isTransient = transientClassifier.isTransient(
            types: Array(Set(typesForFiltering)),
            dataSize: max(dataSize, 10)
        )

        let isSensitive: Bool = {
            guard let primaryText else { return false }
            if case .sensitive = confidentialClassifier.classify(primaryText) {
                return true
            }
            return false
        }()

        let filterDecision = shouldFilter(
            text: primaryText,
            types: Array(Set(typesForFiltering)),
            dataSize: max(dataSize, 10)
        )
        if filterDecision.filtered, let reason = filterDecision.reason {
            Self.logger.info("Filtered clipboard content: \(reason, privacy: .public)")
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
            needsLinkPreview: needsLinkPreview,
            isSensitive: isSensitive,
            isTransient: isTransient
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

    func shouldFilter(text: String?, types: [String], dataSize: Int) -> (
        filtered: Bool, reason: String?
    ) {
        if ignoreTransientContent {
            if transientClassifier.isTransient(types: types, dataSize: dataSize) {
                return (true, "transient content")
            }
        }

        if ignoreConfidentialContent, let text {
            let result = confidentialClassifier.classify(text)
            if case .sensitive(let reason) = result {
                return (true, "confidential: \(reason.rawValue)")
            }
        }

        return (false, nil)
    }

}
