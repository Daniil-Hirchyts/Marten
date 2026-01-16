import AppKit
import ClipboardCore
import UniformTypeIdentifiers

/// Extracts URLs (both file and web) from the pasteboard
struct URLExtractor: PasteboardTypeExtractor {
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let firstURL = urls.first else {
            return nil
        }
        
        if firstURL.isFileURL {
            return extractFileURL(firstURL, displayOrder: displayOrder)
        } else {
            return extractWebURL(firstURL, displayOrder: displayOrder)
        }
    }
    
    private func extractFileURL(_ url: URL, displayOrder: Int16) -> ExtractionResult {
        let fileName = url.lastPathComponent
        let representation = ClipRepresentationPayload(
            kind: .fileURL,
            uti: UTType.fileURL.identifier,
            text: url.path,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            displayOrder: displayOrder
        )
        
        return ExtractionResult(
            representation: representation,
            primaryText: fileName
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
