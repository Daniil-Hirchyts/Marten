import AppKit
import MartenCore
import UniformTypeIdentifiers

/// Extracts URLs (both file and web) from the pasteboard
struct URLExtractor: PasteboardTypeExtractor {
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult? {
        let firstURL: URL? = {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let first = urls.first {
                return first
            }

            let candidates = [
                pasteboard.string(forType: NSPasteboard.PasteboardType(UTType.url.identifier)),
                pasteboard.string(forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier)),
                pasteboard.string(forType: .string)
            ].compactMap { $0 }

            for string in candidates {
                if string.hasPrefix("/") {
                    return URL(fileURLWithPath: string)
                }

                if string.hasPrefix("file://"), let url = URL(string: string) {
                    return url
                }

                if let components = URLComponents(string: string),
                   let scheme = components.scheme?.lowercased(),
                   (scheme == "http" || scheme == "https"),
                   components.host != nil,
                   let url = components.url {
                    return url
                }
            }

            return nil
        }()

        guard let firstURL else {
            return nil
        }
        
        if firstURL.isFileURL {
            return extractFileURL(firstURL, displayOrder: displayOrder)
        } else {
            return extractWebURL(firstURL, displayOrder: displayOrder)
        }
    }
    
    private func extractFileURL(_ url: URL, displayOrder: Int16) -> ExtractionResult? {
        guard let payload = ManagedFileImportService.payload(from: url),
              let representation = payload.representations.first else {
            return nil
        }

        return ExtractionResult(
            representation: ClipRepresentationPayload(
                kind: representation.kind,
                uti: representation.uti,
                text: representation.text,
                data: representation.data,
                fileExtension: representation.fileExtension,
                displayOrder: displayOrder
            ),
            primaryText: payload.primaryText
        )
    }
    
    private func extractWebURL(_ url: URL, displayOrder: Int16) -> ExtractionResult {
        let urlString = url.absoluteString
        let representation = ClipRepresentationPayload(
            kind: .url,
            uti: UTType.url.identifier,
            text: urlString,
            displayOrder: displayOrder
        )
        
        return ExtractionResult(
            representation: representation,
            primaryText: urlString,
            needsLinkPreview: true
        )
    }
}
