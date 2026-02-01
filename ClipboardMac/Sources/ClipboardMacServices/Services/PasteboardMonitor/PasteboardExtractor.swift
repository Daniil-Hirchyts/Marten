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

        var itemType = deriveItemType(from: representations, primaryText: primaryText)
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

    private func deriveItemType(
        from representations: [ClipRepresentationPayload], primaryText: String?
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

        // Check if file is actually an image file by extension
        if hasFile, let text = primaryText {
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "heif", "webp", "svg", "ico"]
            let url = URL(fileURLWithPath: text)
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                return .image
            }
        }

        // Prioritize specific types over generic
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
