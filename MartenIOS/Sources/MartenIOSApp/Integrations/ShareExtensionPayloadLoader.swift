import Foundation
import MartenCore
import UniformTypeIdentifiers

public struct ShareExtensionPayloadCandidate: Sendable {
    public var fileURL: URL?
    public var webURL: URL?
    public var imageData: Data?
    public var imageUTType: UTType?
    public var rtfData: Data?
    public var htmlData: Data?
    public var plainText: String?

    public init(
        fileURL: URL? = nil,
        webURL: URL? = nil,
        imageData: Data? = nil,
        imageUTType: UTType? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        plainText: String? = nil
    ) {
        self.fileURL = fileURL
        self.webURL = webURL
        self.imageData = imageData
        self.imageUTType = imageUTType
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.plainText = plainText
    }
}

public struct ShareExtensionPayloadLoader {
    private let payloadBuilder = ClipboardPayloadBuilder()

    public init() {}

    public func payload(from candidate: ShareExtensionPayloadCandidate) -> ClipItemPayload? {
        payloadBuilder.buildPayload(
            from: ClipboardContent(
                fileURL: candidate.fileURL,
                webURL: candidate.webURL,
                imageData: candidate.imageData,
                imageUTType: candidate.imageUTType,
                rtfData: candidate.rtfData,
                htmlData: candidate.htmlData,
                plainText: candidate.plainText
            )
        )
    }

    public func loadPayloads(from itemProviders: [NSItemProvider]) async -> [ClipItemPayload] {
        var payloads: [ClipItemPayload] = []
        for provider in itemProviders {
            if let candidate = await loadCandidate(from: provider),
                let payload = payload(from: candidate)
            {
                payloads.append(payload)
            }
        }
        return payloads
    }

    private func loadCandidate(from provider: NSItemProvider) async -> ShareExtensionPayloadCandidate? {
        var candidate = ShareExtensionPayloadCandidate()

        let imageTypes: [UTType] = [.png, .jpeg, .tiff, .heic, .heif]
        for imageType in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(imageType.identifier),
                let imageData = await loadData(from: provider, typeIdentifier: imageType.identifier)
            {
                candidate.imageData = imageData
                candidate.imageUTType = imageType
                return candidate
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            let url = await loadURL(from: provider, typeIdentifier: UTType.fileURL.identifier)
        {
            candidate.fileURL = url
            return candidate
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
            let url = await loadURL(from: provider, typeIdentifier: UTType.url.identifier)
        {
            candidate.webURL = url
            return candidate
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
            candidate.rtfData = await loadData(from: provider, typeIdentifier: UTType.rtf.identifier)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
            candidate.htmlData = await loadData(from: provider, typeIdentifier: UTType.html.identifier)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            candidate.plainText = await loadText(from: provider, typeIdentifier: UTType.plainText.identifier)
        }

        if candidate.rtfData != nil || candidate.htmlData != nil || candidate.plainText != nil {
            return candidate
        }

        return nil
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }

                if let textData = item as? Data, let text = String(data: textData, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func loadURL(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                    let text = String(data: data, encoding: .utf8),
                    let url = URL(string: text)
                {
                    continuation.resume(returning: url)
                    return
                }

                if let text = item as? String, let url = URL(string: text) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
