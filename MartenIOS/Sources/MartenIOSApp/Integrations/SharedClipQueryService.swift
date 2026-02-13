import Foundation
import MartenCore

public actor SharedClipQueryService {
    private let store: ClipItemStore
    private let searchService: (any SearchServicing)?

    public init(
        persistenceController: PersistenceController,
        store: ClipItemStore? = nil,
        searchService: (any SearchServicing)? = nil
    ) {
        self.store = store ?? ClipItemStore(persistence: persistenceController)
        self.searchService = searchService
    }

    public func recentItems(
        pinboardID: UUID? = nil,
        limit: Int = 25
    ) throws -> [SharedClipItemSummary] {
        let request = ClipItemSearchRequest(
            query: "",
            pinboardID: pinboardID,
            limit: max(1, limit)
        )
        let items: [ClipItem]
        if let searchService {
            items = try searchService.searchItems(request: request)
        } else {
            items = try store.searchItems(request: request)
        }
        return items.map(mapToSummary)
    }

    public func searchItems(
        query: String,
        pinboardID: UUID? = nil,
        limit: Int = 50
    ) throws -> [SharedClipItemSummary] {
        let request = ClipItemSearchRequest(
            query: query,
            pinboardID: pinboardID,
            limit: max(1, limit)
        )
        let items: [ClipItem]
        if let searchService {
            items = try searchService.searchItems(request: request)
        } else {
            items = try store.searchItems(request: request)
        }
        return items.map(mapToSummary)
    }

    public func pinboards() throws -> [SharedPinboardSummary] {
        let pinboards = try store.fetchPinboards()
        return pinboards
            .sorted { lhs, rhs in
                if lhs.isSystemMarten != rhs.isSystemMarten {
                    return lhs.isSystemMarten
                }
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map {
                SharedPinboardSummary(
                    id: $0.id,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    iconName: $0.iconName,
                    isSystemMarten: $0.isSystemMarten,
                    isShared: $0.isShared,
                    canMakeChanges: $0.canMakeChanges
                )
            }
    }

    private func mapToSummary(_ item: ClipItem) -> SharedClipItemSummary {
        let pinboardIDs = (item.pinboards ?? [])
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }

        let linkPreviewSummary: SharedClipItemSummary.SharedLinkPreviewSummary? = item.linkPreview.map {
            SharedClipItemSummary.SharedLinkPreviewSummary(
                id: $0.id,
                title: normalizedText($0.title),
                siteName: normalizedText($0.siteName),
                imagePath: normalizedText($0.imagePath),
                imageURL: normalizedText($0.imageURL),
                fetchedAt: $0.fetchedAt
            )
        }

        return SharedClipItemSummary(
            id: item.id,
            createdAt: item.createdAt,
            modifiedAt: item.modifiedAt,
            itemType: item.itemTypeValue,
            primaryText: item.primaryText,
            plainText: item.plainTextContent,
            sourceAppName: item.sourceAppName,
            sourceAppBundleID: item.sourceAppBundleID,
            sourceAppIconData: item.sourceAppIconData,
            pinboardIDs: pinboardIDs,
            byteCount: item.byteCount,
            thumbnailPath: thumbnailPath(for: item),
            fileName: fileName(for: item),
            colorHex: colorHex(for: item),
            linkPreview: linkPreviewSummary
        )
    }

    private func thumbnailPath(for item: ClipItem) -> String? {
        if let path = normalizedText(item.thumbnailPath), FileManager.default.fileExists(atPath: path) {
            return path
        }

        guard item.itemTypeValue == .image else { return nil }
        guard let representations = item.representations else { return nil }

        for representation in representations {
            switch representation.kindValue {
            case .png, .jpeg, .tiff, .pdf:
                if let assetRef = representation.assetRef {
                    let fileURL = AssetStore.shared.urlForAsset(
                        assetRef,
                        fileExtension: representation.fileExtension
                    )
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        return fileURL.path
                    }
                }

                if let data = representation.binaryData,
                   let cachedPath = cachedImagePath(
                       for: item,
                       data: data,
                       fileExtension: representation.fileExtension
                   ) {
                    return cachedPath
                }
            case .fileURL:
                if let textData = representation.textData,
                   let path = String(data: textData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            default:
                continue
            }
        }

        return nil
    }

    private func fileName(for item: ClipItem) -> String? {
        guard item.itemTypeValue == .file else { return nil }
        guard let representations = item.representations else {
            return normalizedText(item.primaryText).map { URL(fileURLWithPath: $0).lastPathComponent }
        }

        if let fileRep = representations.first(where: { $0.kindValue == .fileURL }),
           let textData = fileRep.textData,
           let path = String(data: textData, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return normalizedText(item.primaryText).map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private func colorHex(for item: ClipItem) -> String? {
        guard item.itemTypeValue == .color else { return nil }
        let raw = normalizedText(item.plainTextContent) ?? normalizedText(item.primaryText)
        guard let raw else { return nil }
        return ColorHex.normalizedHex(from: raw)
    }

    private func cachedImagePath(
        for item: ClipItem,
        data: Data,
        fileExtension: String?
    ) -> String? {
        guard !data.isEmpty else { return nil }

        let cacheDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MartenSharedClipThumbnailCache", isDirectory: true)

        do {
            if !FileManager.default.fileExists(atPath: cacheDirectoryURL.path) {
                try FileManager.default.createDirectory(
                    at: cacheDirectoryURL,
                    withIntermediateDirectories: true
                )
            }

            let ext = normalizedFileExtension(fileExtension)
            let version = Int64(item.modifiedAt.timeIntervalSince1970 * 1000)
            let fileURL = cacheDirectoryURL
                .appendingPathComponent("\(item.id.uuidString)-\(version)")
                .appendingPathExtension(ext)

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: [.atomic])
            }

            return fileURL.path
        } catch {
            return nil
        }
    }

    private func normalizedFileExtension(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "png"
        }

        let sanitized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return sanitized.isEmpty ? "png" : sanitized
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
