import AppKit
import MartenCore

/// Result from a pasteboard type extraction
public struct ExtractionResult {
    public let representation: ClipRepresentationPayload
    public let primaryText: String?
    public let needsLinkPreview: Bool
    public let textLooksLikeCode: Bool
    
    public init(
        representation: ClipRepresentationPayload,
        primaryText: String? = nil,
        needsLinkPreview: Bool = false,
        textLooksLikeCode: Bool = false
    ) {
        self.representation = representation
        self.primaryText = primaryText
        self.needsLinkPreview = needsLinkPreview
        self.textLooksLikeCode = textLooksLikeCode
    }
}

/// Protocol for extracting specific content types from the pasteboard
public protocol PasteboardTypeExtractor {
    /// Attempts to extract content from the pasteboard
    /// - Parameters:
    ///   - pasteboard: The pasteboard to extract from
    ///   - displayOrder: The display order for the representation
    /// - Returns: An extraction result if content was found, nil otherwise
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult?
}
