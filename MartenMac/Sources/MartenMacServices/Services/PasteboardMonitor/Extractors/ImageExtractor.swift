import AppKit
import MartenCore
import UniformTypeIdentifiers

/// Extracts image data (PNG, JPEG, TIFF, PDF) from the pasteboard
struct ImageExtractor: PasteboardTypeExtractor {
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult? {
        // Try PNG first (highest priority)
        if let pngData = pasteboard.data(forType: .png) {
            return ExtractionResult(
                representation: ClipRepresentationPayload(
                    kind: .png,
                    uti: UTType.png.identifier,
                    data: pngData,
                    fileExtension: "png",
                    displayOrder: displayOrder
                ),
                primaryText: "Image"
            )
        }
        
        // Try JPEG
        if let jpegData = pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) {
            return ExtractionResult(
                representation: ClipRepresentationPayload(
                    kind: .jpeg,
                    uti: UTType.jpeg.identifier,
                    data: jpegData,
                    fileExtension: "jpg",
                    displayOrder: displayOrder
                ),
                primaryText: "Image"
            )
        }
        
        // Try TIFF
        if let tiffData = pasteboard.data(forType: .tiff) {
            return ExtractionResult(
                representation: ClipRepresentationPayload(
                    kind: .tiff,
                    uti: UTType.tiff.identifier,
                    data: tiffData,
                    fileExtension: "tiff",
                    displayOrder: displayOrder
                ),
                primaryText: "Image"
            )
        }
        
        // Try PDF
        if let pdfData = pasteboard.data(forType: .pdf) {
            return ExtractionResult(
                representation: ClipRepresentationPayload(
                    kind: .pdf,
                    uti: UTType.pdf.identifier,
                    data: pdfData,
                    fileExtension: "pdf",
                    displayOrder: displayOrder
                ),
                primaryText: "PDF"
            )
        }
        
        return nil
    }
}
