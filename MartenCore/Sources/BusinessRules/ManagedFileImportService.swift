import Foundation
import UniformTypeIdentifiers

public enum ManagedFileImportService {
    private static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "heif", "webp",
    ]

    public static func payload(
        from fileURL: URL,
        imageData: Data? = nil,
        preferredType: UTType? = nil
    ) -> ClipItemPayload? {
        let fileName = normalizedFileName(from: fileURL)
        let inferredType = preferredType ?? inferredType(for: fileURL)

        if let imagePayload = imagePayloadIfNeeded(
            from: fileURL,
            fileName: fileName,
            imageData: imageData,
            preferredType: inferredType
        ) {
            return imagePayload
        }

        guard let data = loadData(from: fileURL), !data.isEmpty else {
            return nil
        }

        let contentType = inferredType ?? UTType.data
        let fileExtension = normalizedFileExtension(for: fileURL, fallbackType: contentType)
        let representation = ClipRepresentationPayload(
            kind: .custom,
            uti: contentType.identifier,
            data: data,
            fileExtension: fileExtension,
            displayOrder: 0
        )

        return ClipItemPayload(
            representations: [representation],
            primaryText: fileName,
            itemType: .file
        )
    }

    static func loadData(from fileURL: URL) -> Data? {
        let didStart = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try? Data(contentsOf: fileURL)
    }

    static func inferredType(for fileURL: URL) -> UTType? {
        if let type = UTType(filenameExtension: fileURL.pathExtension) {
            return type
        }

        if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }

        return nil
    }

    static func normalizedFileName(from fileURL: URL) -> String {
        let rawName = fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawName.isEmpty ? "File" : rawName
    }

    static func normalizedFileExtension(for fileURL: URL, fallbackType: UTType?) -> String? {
        let pathExt = normalizedFileExtension(fileURL.pathExtension)
        if let pathExt {
            return pathExt
        }

        guard let fallbackExtension = fallbackType?.preferredFilenameExtension else {
            return nil
        }
        return normalizedFileExtension(fallbackExtension)
    }

    static func normalizedFileExtension(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let sanitized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !sanitized.isEmpty, sanitized.count <= 16 else {
            return nil
        }
        return sanitized
    }

    private static func imagePayloadIfNeeded(
        from fileURL: URL,
        fileName: String,
        imageData: Data?,
        preferredType: UTType?
    ) -> ClipItemPayload? {
        let inferredType = preferredType ?? inferredType(for: fileURL)
        let isImageFile =
            inferredType?.conforms(to: .image) == true
            || imageFileExtensions.contains(fileURL.pathExtension.lowercased())

        guard isImageFile else { return nil }
        let payloadData = imageData ?? loadData(from: fileURL)
        guard let payloadData, !payloadData.isEmpty else { return nil }

        return imagePayload(
            data: payloadData,
            type: inferredType,
            fileName: fileName
        )
    }

    private static func imagePayload(
        data: Data,
        type: UTType?,
        fileName: String
    ) -> ClipItemPayload {
        let normalizedType = type ?? .jpeg
        let itemKind: RepresentationKind
        let ext: String

        if normalizedType.conforms(to: .png) {
            itemKind = .png
            ext = "png"
        } else if normalizedType.conforms(to: .tiff) {
            itemKind = .tiff
            ext = "tiff"
        } else if let preferredExtension = normalizedFileExtension(
            normalizedType.preferredFilenameExtension
        ), preferredExtension == "heic" || preferredExtension == "heif" {
            itemKind = .jpeg
            ext = preferredExtension
        } else {
            itemKind = .jpeg
            ext = "jpg"
        }

        let representation = ClipRepresentationPayload(
            kind: itemKind,
            uti: normalizedType.identifier,
            data: data,
            fileExtension: ext,
            displayOrder: 0
        )

        return ClipItemPayload(
            representations: [representation],
            primaryText: fileName,
            itemType: .image
        )
    }
}
