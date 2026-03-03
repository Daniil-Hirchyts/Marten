import AppKit
import Foundation
import MartenCore
import SwiftUI

extension ItemCompactRow {
    var fileNameOnly: String? {
        guard item.itemTypeValue == .file else { return nil }
        let url = URL(fileURLWithPath: item.primaryText ?? "")
        return url.lastPathComponent
    }

    var imageFileName: String? {
        guard item.itemTypeValue == .image else { return nil }

        if let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            !customTitle.isEmpty
        {
            return customTitle
        }

        guard let path = filePathFromRepresentations() else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var imageFileNameShortened: String? {
        guard let fileName = imageFileName else { return nil }
        return shortenFileName(fileName, maxLength: 20)
    }

    func shortenFileName(_ name: String, maxLength: Int) -> String {
        guard name.count > maxLength else { return name }

        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let nameOnly = url.deletingPathExtension().lastPathComponent

        let extWithDot = ext.isEmpty ? "" : ".\(ext)"
        let availableLength = maxLength - extWithDot.count - 3

        guard availableLength > 0 else { return name }

        let startLength = availableLength / 2
        let endLength = availableLength - startLength

        let start = String(nameOnly.prefix(startLength))
        let end = String(nameOnly.suffix(endLength))

        return "\(start)...\(end)\(extWithDot)"
    }

    var fileSizeText: String? {
        guard item.byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
    }

    var urlHost: String {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else { return "URL" }
        return url.host ?? "URL"
    }

    var urlPath: String {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else { return "/" }
        return url.path.isEmpty ? "/" : url.path
    }

    var normalizedPrimaryURL: URL? {
        guard let raw = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }

        if raw.localizedCaseInsensitiveContains("://") {
            return URL(string: raw)
        }

        return URL(string: "https://\(raw)")
    }

    func refreshPreviewAssets() {
        refreshThumbnailImage()
        refreshLinkPreview()
    }

    func refreshLinkPreview() {
        guard item.itemTypeValue == .url else {
            DispatchQueue.main.async {
                linkPreviewResult = nil
                lastLoadedLinkPreviewKey = nil
            }
            return
        }

        if let linkPreview = item.linkPreview {
            let currentPath = linkPreview.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentURL = linkPreview.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheKey = "\(linkPreview.id.uuidString)|\(currentPath ?? "")|\(currentURL ?? "")"
            if lastLoadedLinkPreviewKey == cacheKey {
                return
            }
            DispatchQueue.main.async {
                lastLoadedLinkPreviewKey = cacheKey
            }

            Task {
                let result = await LinkPreviewImageLoader.shared.loadImage(for: linkPreview)
                DispatchQueue.main.async {
                    linkPreviewResult = result
                }
            }
        } else {
            // No LinkPreview entity yet — try favicon from the raw URL
            let rawURL = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cacheKey = "no-lp|\(rawURL)"
            if lastLoadedLinkPreviewKey == cacheKey {
                return
            }
            DispatchQueue.main.async {
                lastLoadedLinkPreviewKey = cacheKey
            }

            guard !rawURL.isEmpty else { return }

            Task {
                let result = await LinkPreviewImageLoader.shared.loadFaviconOnly(urlString: rawURL)
                DispatchQueue.main.async {
                    linkPreviewResult = result
                }
            }
        }
    }

    func refreshThumbnailImage() {
        guard item.itemTypeValue == .image else {
            DispatchQueue.main.async {
                thumbnailImage = nil
                lastLoadedThumbnailPath = nil
            }
            return
        }

        let thumbnailPath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath: String? = {
            guard let thumbnailPath, !thumbnailPath.isEmpty else { return nil }
            return thumbnailPath
        }()
        let cacheKey = thumbnailCacheKey(thumbnailPath: normalizedPath)

        if let cached = ThumbnailImageCache.shared.cachedImage(forKey: cacheKey) {
            DispatchQueue.main.async {
                thumbnailImage = cached
                lastLoadedThumbnailPath = normalizedPath
            }
            return
        }

        if ThumbnailImageCache.shared.hasMissing(forKey: cacheKey) {
            DispatchQueue.main.async {
                thumbnailImage = nil
                lastLoadedThumbnailPath = normalizedPath
            }
            return
        }

        if let normalizedPath {
            if lastLoadedThumbnailPath == normalizedPath, thumbnailImage != nil {
                return
            }
            DispatchQueue.main.async {
                lastLoadedThumbnailPath = normalizedPath
            }

            let representationSnapshots = (item.representations ?? []).map {
                ItemCard.ThumbnailRepresentationSnapshot(
                    kind: $0.kindValue,
                    binaryData: $0.binaryData,
                    assetRef: $0.assetRef,
                    fileExtension: $0.fileExtension,
                    textData: $0.textData
                )
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let image = ThumbnailImageResolver.resolve(
                    thumbnailPath: normalizedPath,
                    snapshots: representationSnapshots
                )

                DispatchQueue.main.async {
                    if let image {
                        ThumbnailImageCache.shared.setImage(image, forKey: cacheKey)
                        thumbnailImage = image
                    } else {
                        ThumbnailImageCache.shared.setMissing(forKey: cacheKey)
                        thumbnailImage = nil
                    }
                }
            }
            return
        }

        DispatchQueue.main.async {
            lastLoadedThumbnailPath = nil
        }
        let representationSnapshots = (item.representations ?? []).map {
            ItemCard.ThumbnailRepresentationSnapshot(
                kind: $0.kindValue,
                binaryData: $0.binaryData,
                assetRef: $0.assetRef,
                fileExtension: $0.fileExtension,
                textData: $0.textData
            )
        }

        guard !representationSnapshots.isEmpty else {
            ThumbnailImageCache.shared.setMissing(forKey: cacheKey)
            DispatchQueue.main.async {
                thumbnailImage = nil
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let image = loadThumbnailImage(from: representationSnapshots)

            DispatchQueue.main.async {
                if let image {
                    ThumbnailImageCache.shared.setImage(image, forKey: cacheKey)
                    thumbnailImage = image
                } else {
                    ThumbnailImageCache.shared.setMissing(forKey: cacheKey)
                    thumbnailImage = nil
                }
            }
        }
    }

    private func loadThumbnailImage(from snapshots: [ItemCard.ThumbnailRepresentationSnapshot]) -> NSImage? {
        ThumbnailImageResolver.resolve(
            thumbnailPath: nil,
            snapshots: snapshots
        )
    }

    private func thumbnailCacheKey(thumbnailPath: String?) -> String {
        if let thumbnailPath {
            return "thumbnail.path.\(thumbnailPath)"
        }
        let version = Int64(item.modifiedAt.timeIntervalSince1970 * 1000)
        let assetSignature = (item.representations ?? [])
            .map { representation in
                let assetRef = representation.assetRef?.uuidString ?? "none"
                let fileExtension = representation.fileExtension?.lowercased() ?? "none"
                return "\(assetRef).\(fileExtension)"
            }
            .sorted()
            .joined(separator: ",")
        return "thumbnail.item.\(item.id.uuidString).\(version).\(assetSignature)"
    }

    func filePathFromRepresentations() -> String? {
        guard let resolvedURL = FileURLAccessResolver.resolvedFileURL(from: item) else {
            return nil
        }
        return resolvedURL.path
    }
}
