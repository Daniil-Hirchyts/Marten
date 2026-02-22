import Foundation
import MartenCore

struct DashboardSharePayloadBuilder {
    private let fileManager: any DashboardFileManaging
    private let imageLoader: any DashboardImageLoading

    init(
        fileManager: any DashboardFileManaging,
        imageLoader: any DashboardImageLoading
    ) {
        self.fileManager = fileManager
        self.imageLoader = imageLoader
    }

    func payloads(for items: [ClipItem]) -> [Any] {
        guard !items.isEmpty else { return [] }

        var payloads: [Any] = []
        for item in items {
            payloads.append(contentsOf: bestEffortPayloads(for: item))
        }

        if payloads.isEmpty {
            let combinedText = items
                .compactMap { normalizedText(for: $0) }
                .joined(separator: "\n")
            if !combinedText.isEmpty {
                payloads = [combinedText]
            }
        }

        return payloads
    }

    func shareURL(for item: ClipItem) -> URL? {
        if item.itemTypeValue == .file,
           let path = item.primaryText,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let fileURL = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            return fileURL
        }

        if item.itemTypeValue == .url,
           let raw = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            if raw.localizedCaseInsensitiveContains("://") {
                return URL(string: raw)
            }
            return URL(string: "https://\(raw)")
        }

        return nil
    }

    func normalizedText(for item: ClipItem) -> String? {
        let text =
            item.plainTextContent?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func bestEffortPayloads(for item: ClipItem) -> [Any] {
        var payloads: [Any] = []

        if let shareURL = shareURL(for: item) {
            payloads.append(shareURL)
        }

        if item.itemTypeValue == .image,
           let imagePath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !imagePath.isEmpty
        {
            if fileManager.fileExists(atPath: imagePath) {
                payloads.append(URL(fileURLWithPath: imagePath))
            }
            if let image = imageLoader.loadImage(atPath: imagePath) {
                payloads.append(image)
            }
        }

        if let text = normalizedText(for: item) {
            payloads.append(text)
        }

        return payloads
    }
}

