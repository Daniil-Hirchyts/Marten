import AppKit
import MartenCore
import ImageIO
import SwiftUI

extension ItemCard {
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
        refreshLinkPreview()
    }

    func refreshStyledPreviewText() {
        guard let styled = item.styledTextContentWithoutTextColor else {
            styledPreviewText = nil
            return
        }

        styledPreviewText = (try? AttributedString(styled, including: \.appKit))
    }

    func refreshLinkPreview() {
        guard item.itemTypeValue == .url else {
            linkPreviewResult = nil
            lastLoadedLinkPreviewKey = nil
            return
        }

        if let linkPreview = item.linkPreview {
            let currentPath = linkPreview.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentURL = linkPreview.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheKey = "\(linkPreview.id.uuidString)|\(currentPath ?? "")|\(currentURL ?? "")"
            if lastLoadedLinkPreviewKey == cacheKey {
                return
            }
            lastLoadedLinkPreviewKey = cacheKey

            Task {
                let result = await LinkPreviewImageLoader.shared.loadImage(for: linkPreview)
                linkPreviewResult = result
            }
        } else {
            // No LinkPreview entity yet — try favicon from the raw URL
            let rawURL = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cacheKey = "no-lp|\(rawURL)"
            if lastLoadedLinkPreviewKey == cacheKey {
                return
            }
            lastLoadedLinkPreviewKey = cacheKey

            guard !rawURL.isEmpty else { return }

            Task {
                let result = await LinkPreviewImageLoader.shared.loadFaviconOnly(urlString: rawURL)
                linkPreviewResult = result
            }
        }
    }

    func resetLinkPreviewState() {
        linkPreviewResult = nil
        lastLoadedLinkPreviewKey = nil
    }

    var linkPreviewTaskID: String {
        let url =
            normalizedPrimaryURL?.absoluteString
            ?? (item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let bannerPath =
            item.linkPreview?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bannerURL =
            item.linkPreview?.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(url)|\(bannerPath)|\(bannerURL)"
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
        }.map(ImagePreviewSourceSnapshot.init(representation:))

        DispatchQueue.global(qos: .userInitiated).async {
            let resolution = ImageResolutionResolver.resolve(from: snapshots)
            DispatchQueue.main.async {
                guard item.objectID == previewItemID else { return }
                guard imageResolutionRequestID == requestID else { return }
                originalImageResolution = resolution
            }
        }
    }

    var imagePreviewRequestPixelSize: Int {
        let requestedPixelSize = Int((cardSize * displayScale).rounded(.up))
        return ImagePreviewRequest.bucketedPixelSize(for: requestedPixelSize)
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

    func refreshFileIcon() {
        guard item.itemTypeValue == .file, let filePath = filePathFromRepresentations() else {
            fileIconImage = nil
            return
        }
        fileIconImage = NSWorkspace.shared.icon(forFile: filePath)
    }

    func filePathFromRepresentations() -> String? {
        guard let resolvedURL = FileURLAccessResolver.resolvedFileURL(from: item) else {
            return nil
        }
        return resolvedURL.path
    }
}

struct ImageResolutionResolver {
    typealias Source = ImagePreviewSourceSnapshot

    static func resolve(from sources: [Source]) -> String? {
        let imageKinds: Set<RepresentationKind> = [.png, .jpeg, .tiff, .pdf]

        for source in sources where imageKinds.contains(source.kind) {
            if let data = source.binaryData, let resolution = resolution(from: data) {
                return resolution
            }

            if let assetRef = source.assetRef,
                let data = try? AssetStore.shared.load(
                    assetRef: assetRef,
                    fileExtension: source.fileExtension
                ),
                let resolution = resolution(from: data)
            {
                return resolution
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
