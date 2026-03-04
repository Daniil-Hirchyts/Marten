import AppKit
import Foundation
import MartenCore
import SwiftUI

extension ItemCompactRow {
    var fileNameOnly: String? {
        guard item.itemTypeValue == .file else { return nil }
        return item.managedFileDisplayName
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
            thumbnailImage = nil
            lastLoadedImageRequestKey = nil
            return
        }

        guard
            let request = ImagePreviewRequest(
                item: item,
                requestedPixelSize: imagePreviewRequestPixelSize
            )
        else {
            thumbnailImage = nil
            lastLoadedImageRequestKey = nil
            return
        }

        let requestKey = request.cacheKey
        if lastLoadedImageRequestKey == requestKey, thumbnailImage != nil {
            return
        }

        lastLoadedImageRequestKey = requestKey
        let previewItemID = item.objectID

        DispatchQueue.global(qos: .userInitiated).async {
            let result = CardImagePreviewLoader.shared.loadPreview(for: request)

            DispatchQueue.main.async {
                guard item.objectID == previewItemID else { return }
                guard lastLoadedImageRequestKey == requestKey else { return }

                if let result {
                    thumbnailImage = result.image
                } else {
                    thumbnailImage = nil
                }
            }
        }
    }

    var imagePreviewRequestPixelSize: Int {
        let requestedPixelSize = Int((CGFloat(120) * displayScale).rounded(.up))
        return ImagePreviewRequest.bucketedPixelSize(for: requestedPixelSize)
    }

    func filePathFromRepresentations() -> String? {
        guard let resolvedURL = FileURLAccessResolver.resolvedFileURL(from: item) else {
            return nil
        }
        return resolvedURL.path
    }
}
