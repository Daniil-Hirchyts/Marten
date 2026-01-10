import AppKit
import ClipboardCore
import Foundation
import UniformTypeIdentifiers

public final class PasteboardExtractor {
    public init() {}

    public func extract(from pasteboard: NSPasteboard) -> ClipItemPayload? {
        var representations: [ClipRepresentationPayload] = []
        var primaryText: String?
        var needsLinkPreview = false
        var textLooksLikeCode = false

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            primaryText = string
            textLooksLikeCode = looksLikeCode(string)
            representations.append(.plainText(string, displayOrder: Int16(representations.count)))
        }

        if let rtfData = pasteboard.data(forType: .rtf) {
            representations.append(
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: UTType.rtf.identifier,
                    data: rtfData,
                    fileExtension: "rtf",
                    displayOrder: Int16(representations.count)
                )
            )

            if primaryText == nil,
               let attributed = try? NSAttributedString(data: rtfData, options: [:], documentAttributes: nil),
               !attributed.string.isEmpty {
                primaryText = attributed.string
            }
        }

        if let htmlData = pasteboard.data(forType: .html) {
            representations.append(
                ClipRepresentationPayload(
                    kind: .html,
                    uti: UTType.html.identifier,
                    data: htmlData,
                    fileExtension: "html",
                    displayOrder: Int16(representations.count)
                )
            )

            if primaryText == nil,
               let attributed = try? NSAttributedString(
                data: htmlData,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
               ),
               !attributed.string.isEmpty {
                primaryText = attributed.string
            }
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            if firstURL.isFileURL {
                let fileName = firstURL.lastPathComponent
                primaryText = primaryText ?? fileName
                representations.append(
                    ClipRepresentationPayload(
                        kind: .fileURL,
                        uti: UTType.fileURL.identifier,
                        text: firstURL.path,
                        fileExtension: firstURL.pathExtension.isEmpty ? nil : firstURL.pathExtension,
                        displayOrder: Int16(representations.count)
                    )
                )
            } else {
                let urlString = firstURL.absoluteString
                primaryText = primaryText ?? urlString
                needsLinkPreview = true
                representations.append(
                    ClipRepresentationPayload(
                        kind: .url,
                        uti: UTType.url.identifier,
                        text: urlString,
                        displayOrder: Int16(representations.count)
                    )
                )
            }
        }

        if let pngData = pasteboard.data(forType: .png) {
            primaryText = primaryText ?? "Image"
            representations.append(
                ClipRepresentationPayload(
                    kind: .png,
                    uti: UTType.png.identifier,
                    data: pngData,
                    fileExtension: "png",
                    displayOrder: Int16(representations.count)
                )
            )
        } else if let jpegData = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) {
            primaryText = primaryText ?? "Image"
            representations.append(
                ClipRepresentationPayload(
                    kind: .jpeg,
                    uti: UTType.jpeg.identifier,
                    data: jpegData,
                    fileExtension: "jpg",
                    displayOrder: Int16(representations.count)
                )
            )
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            primaryText = primaryText ?? "Image"
            representations.append(
                ClipRepresentationPayload(
                    kind: .tiff,
                    uti: UTType.tiff.identifier,
                    data: tiffData,
                    fileExtension: "tiff",
                    displayOrder: Int16(representations.count)
                )
            )
        } else if let pdfData = pasteboard.data(forType: .pdf) {
            primaryText = primaryText ?? "PDF"
            representations.append(
                ClipRepresentationPayload(
                    kind: .pdf,
                    uti: UTType.pdf.identifier,
                    data: pdfData,
                    fileExtension: "pdf",
                    displayOrder: Int16(representations.count)
                )
            )
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

    private func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }

        let newlineCount = trimmed.filter { $0 == "\n" }.count
        let braceCount = trimmed.filter { $0 == "{" || $0 == "}" }.count
        let semicolonCount = trimmed.filter { $0 == ";" }.count
        let keywordHits = ["func ", "class ", "struct ", "let ", "var ", "import ", "def ", "return "]
            .filter { trimmed.contains($0) }
            .count

        if newlineCount >= 1 && (braceCount >= 2 || semicolonCount >= 1) {
            return true
        }

        return keywordHits >= 2
    }
}
