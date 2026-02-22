import Foundation
import MartenCore

enum DashboardCopyMode {
    case bestEffort
    case plainText
}

struct DashboardCopyTextBuilder {
    func buildText(for items: [ClipItem], mode: DashboardCopyMode) -> String {
        items
            .compactMap { item in
                switch mode {
                case .bestEffort:
                    return bestEffortText(for: item)
                case .plainText:
                    return plainText(for: item)
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func bestEffortText(for item: ClipItem) -> String? {
        item.plainTextContent?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func plainText(for item: ClipItem) -> String? {
        if let plainText = item.plainTextContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plainText.isEmpty
        {
            return plainText
        }
        return item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

