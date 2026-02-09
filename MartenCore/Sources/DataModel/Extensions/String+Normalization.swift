import Foundation

public extension String {
    func normalizedForSearch() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded
    }
}
