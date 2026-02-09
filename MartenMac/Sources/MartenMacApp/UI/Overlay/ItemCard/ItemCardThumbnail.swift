import AppKit
import MartenCore
import ImageIO
import LinkPresentation
import SwiftUI

extension ItemCard {
    var fileNameOnly: String? {
        guard item.itemTypeValue == .file else { return nil }
        let url = URL(fileURLWithPath: cached.primaryTitle)
        return url.lastPathComponent
    }

    var imageFileName: String? {
        guard item.itemTypeValue == .image else { return nil }

        if let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            !customTitle.isEmpty
        {
            return customTitle
        }

        guard let reps = item.representations,
            let fileRep = reps.first(where: { $0.kindValue == .fileURL }),
            let data = fileRep.textData,
            let path = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let url = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
        return url.lastPathComponent
    }

    var imageFileNameShortened: String? {
        guard let fileName = imageFileName else { return nil }
        return shortenFileName(fileName, maxLength: 20)
    }

    var imageResolution: String? {
        guard item.itemTypeValue == .image else { return nil }
        return originalImageResolution
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

    var urlDisplayText: String {
        if let normalizedPrimaryURL {
            return normalizedPrimaryURL.absoluteString
        }
        return item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        refreshImageResolution()
        refreshFileIcon()
        refreshURLBannerImage()
    }

    func refreshStyledPreviewText() {
        guard item.itemTypeValue == .richText else {
            styledPreviewText = nil
            return
        }

        guard let styled = item.styledTextContentWithoutTextColor else {
            styledPreviewText = nil
            return
        }

        styledPreviewText = (try? AttributedString(styled, including: \.appKit))
    }

    func refreshURLBannerImage() {
        guard item.itemTypeValue == .url else {
            urlBannerImage = nil
            lastLoadedURLBannerPath = nil
            lastFetchedURLBannerURLString = nil
            return
        }

        guard
            let path = item.linkPreview?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            lastLoadedURLBannerPath = nil
            return
        }

        if lastLoadedURLBannerPath == path {
            return
        }
        lastLoadedURLBannerPath = path

        DispatchQueue.global(qos: .userInitiated).async {
            let image = NSImage(contentsOfFile: path)
            DispatchQueue.main.async {
                if let image {
                    urlBannerImage = image
                }
            }
        }
    }

    func resetURLBannerState() {
        urlBannerImage = nil
        lastLoadedURLBannerPath = nil
        lastFetchedURLBannerURLString = nil
    }

    var urlBannerTaskID: String {
        let url =
            normalizedPrimaryURL?.absoluteString
            ?? (item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let bannerPath =
            item.linkPreview?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(url)|\(bannerPath)"
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
            metadata = try await provider.startFetchingMetadata(for: url)
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

    func refreshImageResolution() {
        let requestID = UUID()
        imageResolutionRequestID = requestID

        guard item.itemTypeValue == .image else {
            originalImageResolution = nil
            return
        }

        let previewItemID = item.objectID
        let snapshots = (item.representations ?? []).sorted {
            $0.displayOrder < $1.displayOrder
        }.map {
            ImageResolutionResolver.Source(
                kind: $0.kindValue,
                binaryData: $0.binaryData,
                assetRef: $0.assetRef,
                fileExtension: $0.fileExtension,
                textData: $0.textData
            )
        }
        let thumbnailPath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThumbnailPath: String? = {
            guard let thumbnailPath, !thumbnailPath.isEmpty else { return nil }
            return thumbnailPath
        }()

        DispatchQueue.global(qos: .userInitiated).async {
            let resolution = ImageResolutionResolver.resolve(
                from: snapshots,
                thumbnailPath: normalizedThumbnailPath
            )
            DispatchQueue.main.async {
                guard item.objectID == previewItemID else { return }
                guard imageResolutionRequestID == requestID else { return }
                originalImageResolution = resolution
            }
        }
    }

    func refreshThumbnailImage() {
        guard item.itemTypeValue == .image else {
            thumbnailImage = nil
            lastLoadedThumbnailPath = nil
            return
        }

        let thumbnailPath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath: String? = {
            guard let thumbnailPath, !thumbnailPath.isEmpty else { return nil }
            return thumbnailPath
        }()
        let cacheKey = thumbnailCacheKey(thumbnailPath: normalizedPath)

        if let cached = ThumbnailImageCache.shared.cachedImage(forKey: cacheKey) {
            thumbnailImage = cached
            lastLoadedThumbnailPath = normalizedPath
            return
        }

        if ThumbnailImageCache.shared.hasMissing(forKey: cacheKey) {
            thumbnailImage = nil
            lastLoadedThumbnailPath = normalizedPath
            return
        }

        if let normalizedPath {
            if lastLoadedThumbnailPath == normalizedPath, thumbnailImage != nil {
                return
            }
            lastLoadedThumbnailPath = normalizedPath

            DispatchQueue.global(qos: .userInitiated).async {
                let image: NSImage?
                if let data = try? Data(contentsOf: URL(fileURLWithPath: normalizedPath)) {
                    image = NSImage(data: data)
                } else {
                    image = nil
                }

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

        lastLoadedThumbnailPath = nil
        let representationSnapshots = (item.representations ?? []).map {
            ThumbnailRepresentationSnapshot(
                kind: $0.kindValue,
                binaryData: $0.binaryData,
                textData: $0.textData
            )
        }

        guard !representationSnapshots.isEmpty else {
            ThumbnailImageCache.shared.setMissing(forKey: cacheKey)
            thumbnailImage = nil
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

    private struct ThumbnailRepresentationSnapshot {
        let kind: RepresentationKind
        let binaryData: Data?
        let textData: Data?
    }

    private func thumbnailCacheKey(thumbnailPath: String?) -> String {
        if let thumbnailPath {
            return "thumbnail.path.\(thumbnailPath)"
        }
        let version = Int64(item.modifiedAt.timeIntervalSince1970 * 1000)
        return "thumbnail.item.\(item.id.uuidString).\(version)"
    }

    private func loadThumbnailImage(from snapshots: [ThumbnailRepresentationSnapshot]) -> NSImage? {
        for snapshot in snapshots where snapshot.kind == .png || snapshot.kind == .jpeg || snapshot.kind == .tiff {
            if let data = snapshot.binaryData, let image = NSImage(data: data) {
                return image
            }
        }

        if let fileRef = snapshots.first(where: { $0.kind == .fileURL }),
            let data = fileRef.textData,
            let path = String(data: data, encoding: .utf8)
        {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return NSImage(contentsOfFile: trimmed)
            }
        }

        return nil
    }

    func refreshFileIcon() {
        guard item.itemTypeValue == .file, let filePath = filePathFromRepresentations() else {
            fileIconImage = nil
            return
        }
        fileIconImage = NSWorkspace.shared.icon(forFile: filePath)
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

struct ImageResolutionResolver {
    struct Source {
        let kind: RepresentationKind
        let binaryData: Data?
        let assetRef: UUID?
        let fileExtension: String?
        let textData: Data?
    }

    static func resolve(from sources: [Source], thumbnailPath: String?) -> String? {
        let imageKinds: Set<RepresentationKind> = [.png, .jpeg, .tiff, .pdf]

        for source in sources where imageKinds.contains(source.kind) {
            if let data = source.binaryData, let resolution = resolution(from: data) {
                return resolution
            }

            if let assetRef = source.assetRef {
                let path = AssetStore.shared.urlForAsset(
                    assetRef,
                    fileExtension: source.fileExtension
                ).path
                if let resolution = resolution(fromFileAtPath: path) {
                    return resolution
                }
            }
        }

        if let fileURLSource = sources.first(where: { $0.kind == .fileURL }),
            let data = fileURLSource.textData,
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
            let resolution = resolution(fromFileAtPath: path)
        {
            return resolution
        }

        if let thumbnailPath, let resolution = resolution(fromFileAtPath: thumbnailPath) {
            return resolution
        }

        return nil
    }

    private static func resolution(from data: Data) -> String? {
        if
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let resolution = resolution(from: properties)
        {
            return resolution
        }

        guard let image = NSImage(data: data) else { return nil }
        return resolution(from: image)
    }

    private static func resolution(fromFileAtPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)

        if
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let resolution = resolution(from: properties)
        {
            return resolution
        }

        guard let image = NSImage(contentsOfFile: path) else { return nil }
        return resolution(from: image)
    }

    private static func resolution(from properties: [CFString: Any]) -> String? {
        guard
            let width = intValue(from: properties[kCGImagePropertyPixelWidth]),
            let height = intValue(from: properties[kCGImagePropertyPixelHeight]),
            width > 0,
            height > 0
        else {
            return nil
        }

        return "\(width)×\(height)"
    }

    private static func resolution(from image: NSImage) -> String? {
        let bitmapRepresentations = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if
            let bestRepresentation = bitmapRepresentations.max(by: {
                ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
            }),
            bestRepresentation.pixelsWide > 0,
            bestRepresentation.pixelsHigh > 0
        {
            return "\(bestRepresentation.pixelsWide)×\(bestRepresentation.pixelsHigh)"
        }

        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        default:
            return nil
        }
    }
}
