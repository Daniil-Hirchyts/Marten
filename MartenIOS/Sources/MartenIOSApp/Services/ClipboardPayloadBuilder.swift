import Foundation
import MartenCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

protocol ClipboardReading {
    func readContent() -> ClipboardContent?
}

struct ClipboardContent {
    var fileURL: URL?
    var webURL: URL?
    var imageData: Data?
    var imageUTType: UTType?
    var rtfData: Data?
    var htmlData: Data?
    var plainText: String?
}

struct ClipboardPayloadBuilder {
    func buildPayload(from content: ClipboardContent) -> ClipItemPayload? {
        if let fileURL = content.fileURL {
            return buildFilePayload(fileURL)
        }

        if let webURL = content.webURL {
            return buildWebURLPayload(webURL)
        }

        if let imageData = content.imageData {
            return buildImagePayload(data: imageData, type: content.imageUTType)
        }

        if content.rtfData != nil || content.htmlData != nil {
            return buildRichTextPayload(
                rtfData: content.rtfData,
                htmlData: content.htmlData,
                plainText: content.plainText
            )
        }

        if let plainText = content.plainText?.trimmingCharacters(in: .whitespacesAndNewlines),
            !plainText.isEmpty
        {
            return buildPlainTextPayload(plainText)
        }

        return nil
    }

    private func buildFilePayload(_ fileURL: URL) -> ClipItemPayload {
        let extensionName = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension
        let bookmarkData = try? fileURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let representation = ClipRepresentationPayload(
            kind: .fileURL,
            uti: UTType.fileURL.identifier,
            text: fileURL.path,
            data: bookmarkData,
            fileExtension: extensionName,
            displayOrder: 0
        )

        let imageExtensions = Set([
            "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp",
        ])

        let itemType: ItemType = imageExtensions.contains(fileURL.pathExtension.lowercased()) ? .image : .file

        return ClipItemPayload(
            representations: [representation],
            primaryText: fileURL.lastPathComponent,
            itemType: itemType
        )
    }

    private func buildWebURLPayload(_ url: URL) -> ClipItemPayload {
        let text = url.absoluteString
        let representation = ClipRepresentationPayload(
            kind: .url,
            uti: UTType.url.identifier,
            text: text,
            displayOrder: 0
        )

        return ClipItemPayload(
            representations: [representation],
            primaryText: text,
            itemType: .url,
            needsLinkPreview: true
        )
    }

    private func buildImagePayload(data: Data, type: UTType?) -> ClipItemPayload {
        let normalizedType = type ?? .jpeg
        let itemKind: RepresentationKind
        let ext: String

        switch normalizedType {
        case .png:
            itemKind = .png
            ext = "png"
        case .tiff:
            itemKind = .tiff
            ext = "tiff"
        default:
            itemKind = .jpeg
            ext = "jpg"
        }

        let representation = ClipRepresentationPayload(
            kind: itemKind,
            uti: normalizedType.identifier,
            data: data,
            fileExtension: ext,
            displayOrder: 0
        )

        return ClipItemPayload(
            representations: [representation],
            primaryText: "Image",
            itemType: .image
        )
    }

    private func buildRichTextPayload(
        rtfData: Data?,
        htmlData: Data?,
        plainText: String?
    ) -> ClipItemPayload {
        var representations: [ClipRepresentationPayload] = []
        var displayOrder: Int16 = 0

        let normalizedPlainText = plainText?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedPlainText, !normalizedPlainText.isEmpty {
            representations.append(.plainText(normalizedPlainText, displayOrder: displayOrder))
            displayOrder += 1
        }

        if let rtfData, !rtfData.isEmpty {
            representations.append(
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: UTType.rtf.identifier,
                    data: rtfData,
                    fileExtension: "rtf",
                    displayOrder: displayOrder
                )
            )
            displayOrder += 1
        }

        if let htmlData, !htmlData.isEmpty {
            representations.append(
                ClipRepresentationPayload(
                    kind: .html,
                    uti: UTType.html.identifier,
                    data: htmlData,
                    fileExtension: "html",
                    displayOrder: displayOrder
                )
            )
            displayOrder += 1
        }

        if representations.isEmpty, let normalizedPlainText, !normalizedPlainText.isEmpty {
            representations.append(.plainText(normalizedPlainText))
        }

        return ClipItemPayload(
            representations: representations,
            primaryText: normalizedPlainText,
            itemType: .richText
        )
    }

    private func buildPlainTextPayload(_ text: String) -> ClipItemPayload {
        ClipItemPayload(
            representations: [.plainText(text)],
            primaryText: text,
            itemType: classifyPlainText(text)
        )
    }

    private func classifyPlainText(_ text: String) -> ItemType {
        if looksLikeHexColor(text) {
            return .color
        }

        if looksLikeCode(text) {
            return .code
        }

        return .text
    }

    private func looksLikeHexColor(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var candidate = trimmed
        if candidate.lowercased().hasPrefix("0x") {
            candidate = String(candidate.dropFirst(2))
        }
        if candidate.hasPrefix("#") {
            candidate = String(candidate.dropFirst())
        }

        let cleaned = candidate.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 3 || cleaned.count == 6 || cleaned.count == 8 else {
            return false
        }

        return cleaned.allSatisfy(\.isHexDigit)
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }

        let newlineCount = trimmed.filter { $0 == "\n" }.count
        let braceCount = trimmed.filter { $0 == "{" || $0 == "}" }.count
        let semicolonCount = trimmed.filter { $0 == ";" }.count

        let keywordHits = [
            "func ", "class ", "struct ", "let ", "var ", "import ", "def ", "return ",
        ]
            .filter { trimmed.contains($0) }
            .count

        if newlineCount >= 1 && (braceCount >= 2 || semicolonCount >= 1) {
            return true
        }

        return keywordHits >= 2
    }
}

struct SystemClipboardReader: ClipboardReading {
    func readContent() -> ClipboardContent? {
        #if canImport(UIKit)
        return readUIKitClipboard()
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    private func readUIKitClipboard() -> ClipboardContent? {
        let pasteboard = UIPasteboard.general
        var content = ClipboardContent()

        if let urls = pasteboard.urls,
            let fileURL = urls.first(where: \.isFileURL)
        {
            content.fileURL = fileURL
        }

        if content.fileURL == nil,
            let firstURL = pasteboard.url,
            firstURL.isFileURL
        {
            content.fileURL = firstURL
        }

        if content.fileURL == nil,
            let urls = pasteboard.urls,
            let webURL = urls.first(where: { !$0.isFileURL })
        {
            content.webURL = webURL
        }

        if content.webURL == nil,
            let firstURL = pasteboard.url,
            !firstURL.isFileURL
        {
            content.webURL = firstURL
        }

        if let webURLString = pasteboard.string,
            content.webURL == nil,
            let parsed = URL(string: webURLString),
            let scheme = parsed.scheme?.lowercased(),
            (scheme == "http" || scheme == "https")
        {
            content.webURL = parsed
        }

        if let rtfData = pasteboard.data(forPasteboardType: UTType.rtf.identifier), !rtfData.isEmpty {
            content.rtfData = rtfData
        }

        if let htmlData = pasteboard.data(forPasteboardType: UTType.html.identifier), !htmlData.isEmpty {
            content.htmlData = htmlData
        }

        if let image = pasteboard.image {
            if let pngData = image.pngData() {
                content.imageData = pngData
                content.imageUTType = .png
            } else if let jpegData = image.jpegData(compressionQuality: 0.95) {
                content.imageData = jpegData
                content.imageUTType = .jpeg
            }
        } else if let images = pasteboard.images, let first = images.first {
            if let pngData = first.pngData() {
                content.imageData = pngData
                content.imageUTType = .png
            } else if let jpegData = first.jpegData(compressionQuality: 0.95) {
                content.imageData = jpegData
                content.imageUTType = .jpeg
            }
        }

        if let plain = pasteboard.string, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content.plainText = plain
        }

        if content.fileURL == nil,
            content.webURL == nil,
            content.imageData == nil,
            content.rtfData == nil,
            content.htmlData == nil,
            content.plainText == nil
        {
            return nil
        }

        return content
    }
    #endif
}
