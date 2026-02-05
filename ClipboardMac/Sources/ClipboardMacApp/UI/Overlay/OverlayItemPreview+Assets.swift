import AppKit
import ClipboardCore
import LinkPresentation
import SwiftUI

extension OverlayItemPreview {
    func refreshCachedProperties() {
        cachedProps = OverlayPerformanceSignposts.measure("CachedItemProperties") {
            CachedItemProperties(item: item)
        }
    }

    func refreshStyledTextPreview() {
        guard item.itemTypeValue == .richText else {
            styledRichTextPreview = nil
            return
        }

        guard let styled = item.styledTextContentWithoutTextColor else {
            styledRichTextPreview = nil
            return
        }

        styledRichTextPreview = OverlayPerformanceSignposts.measure("AttributedString") {
            try? AttributedString(styled, including: \.appKit)
        }
    }

    func loadAssetsIfNeeded() {
        loadImageIfNeeded()
        loadFileIconIfNeeded()
        loadURLBannerIfNeeded()
    }

    func loadURLBannerIfNeeded() {
        guard item.itemTypeValue == .url else {
            urlBannerImage = nil
            lastLoadedURLBannerPath = nil
            return
        }

        guard
            let path = item.linkPreview?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            urlBannerImage = nil
            lastLoadedURLBannerPath = nil
            return
        }

        if lastLoadedURLBannerPath == path {
            return
        }
        lastLoadedURLBannerPath = path

        DispatchQueue.global(qos: .userInitiated).async {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let maxPixel = 1200 * scale
            let img = OverlayPerformanceSignposts.measure("URLBannerDecode") {
                ImageDownsampler.downsampledImage(atPath: path, maxPixelSize: maxPixel)
            }
            DispatchQueue.main.async {
                urlBannerImage = img
            }
        }
    }

    func fetchURLBannerIfNeeded() async {
        guard item.itemTypeValue == .url else { return }

        guard let url = normalizedPrimaryURL, let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return
        }
        let urlString = url.absoluteString

        if urlBannerImage != nil {
            lastFetchedURLBannerURLString = urlString
            return
        }

        if lastFetchedURLBannerURLString == urlString {
            return
        }

        let provider = LPMetadataProvider()
        let metadata: LPLinkMetadata
        do {
            metadata = try await OverlayPerformanceSignposts.measure("LPMetadataFetch") {
                try await provider.startFetchingMetadata(for: url)
            }
        } catch {
            return
        }

        let itemProvider = metadata.imageProvider ?? metadata.iconProvider
        guard let itemProvider else { return }

        let image: NSImage?
        do {
            image = try await loadNSImage(from: itemProvider)
        } catch {
            return
        }

        guard let image else { return }
        await MainActor.run {
            if urlBannerImage == nil {
                urlBannerImage = image
            }
        }
    }

    func loadNSImage(from provider: NSItemProvider) async throws -> NSImage {
        try await OverlayPerformanceSignposts.measure("NSItemProviderImage") {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadObject(ofClass: NSImage.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let image = object as? NSImage else {
                        continuation.resume(throwing: NSError(domain: "URLBannerPreview", code: 1))
                        return
                    }
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func loadImageIfNeeded() {
        guard item.itemTypeValue == .image else {
            image = nil
            return
        }

        if let path = nonEmptyText(item.thumbnailPath) {
            DispatchQueue.global(qos: .userInitiated).async {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let maxPixel = 1200 * scale
                let img = OverlayPerformanceSignposts.measure("PreviewImageDecode") {
                    ImageDownsampler.downsampledImage(atPath: path, maxPixelSize: maxPixel)
                }
                DispatchQueue.main.async {
                    image = img
                }
            }
            return
        }

        let representations = item.representations ?? []
        let imageData: [Data] = representations.compactMap { rep in
            let kind = rep.kindValue
            guard kind == .png || kind == .jpeg || kind == .tiff else {
                return nil
            }
            return rep.binaryData
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for data in imageData {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let maxPixel = 1200 * scale
                let img = OverlayPerformanceSignposts.measure("PreviewImageDecode") {
                    ImageDownsampler.downsampledImage(fromData: data, maxPixelSize: maxPixel)
                }
                if let img {
                    DispatchQueue.main.async { image = img }
                    return
                }
            }
            DispatchQueue.main.async { image = nil }
        }
    }

    func loadFileIconIfNeeded() {
        guard item.itemTypeValue == .file, let path = filePathFromRepresentations() else {
            fileIcon = nil
            return
        }
        fileIcon = NSWorkspace.shared.icon(forFile: path)
    }

    func filePathFromRepresentations() -> String? {
        guard let reps = item.representations else { return nil }
        guard let rep = reps.first(where: { $0.kindValue == .fileURL }) else { return nil }
        guard let data = rep.textData, let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
