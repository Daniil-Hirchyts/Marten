import XCTest
@testable import MartenCore

final class PlainTextConversionTests: XCTestCase {
    
    // MARK: - Plain Text Representation
    
    func testPlainTextContentReturnsPlainTextRepresentation() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .plainText,
                    uti: "public.utf8-plain-text",
                    text: "Hello, World!"
                )
            ],
            primaryText: "Hello, World!",
            itemType: .text
        )
        let item = try store.createItem(payload: payload)
        
        XCTAssertEqual(item.plainTextContent, "Hello, World!")
    }
    
    // MARK: - RTF Conversion
    
    func testPlainTextContentConvertsRTFToPlainText() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        // Minimal RTF with bold formatting
        let rtfString = "{\\rtf1\\ansi{\\b Bold Text} and normal text}"
        
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: "public.rtf",
                    text: rtfString,  // RTF goes in text field -> textData
                    fileExtension: "rtf"
                )
            ],
            primaryText: nil,
            itemType: .richText
        )
        let item = try store.createItem(payload: payload)
        
        let plainText = item.plainTextContent
        XCTAssertNotNil(plainText)
        XCTAssertTrue(plainText?.contains("Bold Text") ?? false)
        XCTAssertTrue(plainText?.contains("normal text") ?? false)
        // RTF formatting tags should be stripped
        XCTAssertFalse(plainText?.contains("\\rtf") ?? true)
        XCTAssertFalse(plainText?.contains("\\b") ?? true)
    }
    
    // MARK: - HTML Conversion
    
    func testPlainTextContentConvertsHTMLToPlainText() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        let htmlString = "<html><body><h1>Title</h1><p>Paragraph with <strong>bold</strong> text.</p></body></html>"
        
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .html,
                    uti: "public.html",
                    text: htmlString,  // HTML goes in text field -> textData
                    fileExtension: "html"
                )
            ],
            primaryText: nil,
            itemType: .richText
        )
        let item = try store.createItem(payload: payload)
        
        let plainText = item.plainTextContent
        XCTAssertNotNil(plainText)
        XCTAssertTrue(plainText?.contains("Title") ?? false)
        XCTAssertTrue(plainText?.contains("Paragraph") ?? false)
        XCTAssertTrue(plainText?.contains("bold") ?? false)
        // HTML tags should be stripped
        XCTAssertFalse(plainText?.contains("<h1>") ?? true)
        XCTAssertFalse(plainText?.contains("<strong>") ?? true)
        XCTAssertFalse(plainText?.contains("</p>") ?? true)
    }
    
    // MARK: - URL Items
    
    func testPlainTextContentReturnsURLForURLItems() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        let urlString = "https://example.com/path?query=value"
        
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .url,
                    uti: "public.url",
                    text: urlString
                )
            ],
            primaryText: urlString,
            itemType: .url
        )
        let item = try store.createItem(payload: payload)
        
        XCTAssertEqual(item.plainTextContent, urlString)
    }
    
    // MARK: - Fallback to primaryText
    
    func testPlainTextContentFallsBackToPrimaryText() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        // Image item with primaryText but no text representation
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .png,
                    uti: "public.png",
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    fileExtension: "png"
                )
            ],
            primaryText: "Screenshot 2026-01-16",
            itemType: .image
        )
        let item = try store.createItem(payload: payload)
        
        XCTAssertEqual(item.plainTextContent, "Screenshot 2026-01-16")
    }
    
    // MARK: - No Plain Text Available
    
    func testPlainTextContentReturnsNilWhenNoTextAvailable() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        // Image item with no primaryText
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .png,
                    uti: "public.png",
                    data: Data([0x89, 0x50, 0x4E, 0x47]),
                    fileExtension: "png"
                )
            ],
            primaryText: nil,
            itemType: .image
        )
        let item = try store.createItem(payload: payload)
        
        XCTAssertNil(item.plainTextContent)
    }
    
    // MARK: - Priority Order
    
    func testPlainTextContentPrefersPlainTextOverRTF() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        let rtfString = "{\\rtf1\\ansi RTF version}"
        
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: "public.rtf",
                    text: rtfString,
                    fileExtension: "rtf",
                    displayOrder: 1
                ),
                ClipRepresentationPayload(
                    kind: .plainText,
                    uti: "public.utf8-plain-text",
                    text: "Plain text version",
                    displayOrder: 0
                )
            ],
            primaryText: "Plain text version",
            itemType: .richText
        )
        let item = try store.createItem(payload: payload)
        
        // Should prefer plain text representation over RTF conversion
        XCTAssertEqual(item.plainTextContent, "Plain text version")
    }
    
    func testPlainTextContentPrefersRTFOverHTML() throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipItemStore(persistence: persistence)
        
        let rtfString = "{\\rtf1\\ansi RTF content here}"
        let htmlString = "<html><body>HTML content here</body></html>"
        
        let payload = ClipItemPayload(
            representations: [
                ClipRepresentationPayload(
                    kind: .html,
                    uti: "public.html",
                    text: htmlString,
                    fileExtension: "html",
                    displayOrder: 0
                ),
                ClipRepresentationPayload(
                    kind: .rtf,
                    uti: "public.rtf",
                    text: rtfString,
                    fileExtension: "rtf",
                    displayOrder: 1
                )
            ],
            primaryText: nil,
            itemType: .richText
        )
        let item = try store.createItem(payload: payload)
        
        // Should prefer RTF over HTML (based on implementation order in plainTextContent)
        let plainText = item.plainTextContent
        XCTAssertNotNil(plainText)
        XCTAssertTrue(plainText?.contains("RTF content here") ?? false)
    }
}
