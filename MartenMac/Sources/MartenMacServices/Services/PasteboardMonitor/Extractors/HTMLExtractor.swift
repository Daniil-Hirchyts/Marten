import AppKit
import MartenCore
import UniformTypeIdentifiers

/// Extracts HTML data from the pasteboard
struct HTMLExtractor: PasteboardTypeExtractor {
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult? {
        guard let htmlData = pasteboard.data(forType: .html) else {
            return nil
        }
        
        let representation = ClipRepresentationPayload(
            kind: .html,
            uti: UTType.html.identifier,
            data: htmlData,
            fileExtension: "html",
            displayOrder: displayOrder
        )
        
        // Try to extract primary text from HTML
        var primaryText: String?
        if let attributed = try? NSAttributedString(
            data: htmlData,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ),
           !attributed.string.isEmpty {
            primaryText = attributed.string
        }
        
        return ExtractionResult(
            representation: representation,
            primaryText: primaryText
        )
    }
}
