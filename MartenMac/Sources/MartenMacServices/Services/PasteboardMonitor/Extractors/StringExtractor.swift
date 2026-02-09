import AppKit
import MartenCore
import UniformTypeIdentifiers

/// Extracts plain text from the pasteboard
struct StringExtractor: PasteboardTypeExtractor {
    func extract(from pasteboard: NSPasteboard, displayOrder: Int16) -> ExtractionResult? {
        guard let string = pasteboard.string(forType: .string), !string.isEmpty else {
            return nil
        }
        
        return ExtractionResult(
            representation: .plainText(string, displayOrder: displayOrder),
            primaryText: string,
            textLooksLikeCode: looksLikeCode(string)
        )
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
