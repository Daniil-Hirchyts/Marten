import AppKit
import MartenCore
import UniformTypeIdentifiers

/// Extracts RTF data from the pasteboard
struct RTFExtractor: PasteboardTypeExtractor {
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult? {
        guard let rtfData = pasteboard.data(forType: .rtf) else {
            return nil
        }
        
        let representation = ClipRepresentationPayload(
            kind: .rtf,
            uti: UTType.rtf.identifier,
            data: rtfData,
            fileExtension: "rtf",
            displayOrder: displayOrder
        )
        
        // Try to extract primary text from RTF
        var primaryText: String?
        if let attributed = try? NSAttributedString(data: rtfData, options: [:], documentAttributes: nil),
           !attributed.string.isEmpty {
            primaryText = attributed.string
        }
        
        return ExtractionResult(
            representation: representation,
            primaryText: primaryText
        )
    }
}
