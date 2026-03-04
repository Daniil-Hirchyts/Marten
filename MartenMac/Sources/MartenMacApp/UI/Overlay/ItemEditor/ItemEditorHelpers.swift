import AppKit
import MartenCore
import MartenMacServices
import SwiftUI

enum RotationDirection {
    case left
    case right
}

struct ItemEditorAppleIntelligencePreview: Identifiable {
    let id = UUID()
    let action: AppleIntelligenceTextAction
    let target: ItemEditorAIResolvedTarget
    let transformedText: String
}

enum ItemEditorHelpers {
    static func hasRichFormatting(_ attributedText: NSAttributedString) -> Bool {
        guard attributedText.length > 0 else { return false }

        var hasFormatting = false
        attributedText.enumerateAttributes(
            in: NSRange(location: 0, length: attributedText.length)
        ) { attributes, _, stop in
            if let font = attributes[.font] as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.bold)
                    || font.fontDescriptor.symbolicTraits.contains(.italic)
                {
                    hasFormatting = true
                    stop.pointee = true
                    return
                }
            }

            if attributes[.underlineStyle] != nil || attributes[.strikethroughStyle] != nil {
                hasFormatting = true
                stop.pointee = true
                return
            }

            if attributes[.paragraphStyle] != nil {
                hasFormatting = true
                stop.pointee = true
            }
        }

        return hasFormatting
    }

    static func fileURLPath(from item: ClipItem) -> String? {
        FileURLAccessResolver.resolvedFileURL(from: item)?.path
    }

    static func exportedFileURL(from item: ClipItem) -> URL? {
        try? ManagedFileAccess.exportURL(for: item)
    }

    static func imageFromRepresentations(for item: ClipItem) -> NSImage? {
        let representations = (item.representations ?? []).sorted { $0.displayOrder < $1.displayOrder }

        for rep in representations {
            let kind = rep.kindValue
            if kind == .png || kind == .jpeg || kind == .tiff || kind == .pdf {
                if let assetRef = rep.assetRef,
                    let url = AssetStore.shared.existingURLForAsset(
                        assetRef,
                        fileExtension: rep.fileExtension
                    ),
                    let image = NSImage(contentsOf: url)
                {
                    return image
                }

                if let data = rep.binaryData, let image = NSImage(data: data) {
                    return image
                }
            }

            if kind == .fileURL,
                let textData = rep.textData,
                let rawPath = String(data: textData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                rawPath.isEmpty == false
            {
                let url: URL
                if let resolvedURL = URL(string: rawPath), resolvedURL.isFileURL {
                    url = resolvedURL
                } else {
                    url = URL(fileURLWithPath: rawPath)
                }

                if let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }

        return nil
    }

    static func nsRange(from selection: TextSelection?, in text: String) -> NSRange? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return NSRange(range, in: text)
        case .multiSelection(let ranges):
            guard let firstRange = ranges.ranges.first else { return nil }
            return NSRange(firstRange, in: text)
        @unknown default:
            return nil
        }
    }

    static func imageDataPNG(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }

    static func applyRotation(to image: NSImage, degrees: Double) -> NSImage {
        if degrees == 0 {
            return image
        }

        let radians = CGFloat(degrees * .pi / 180.0)

        let originalSize = image.size
        let rotatedWidth =
            abs(originalSize.width * cos(radians)) + abs(originalSize.height * sin(radians))
        let rotatedHeight =
            abs(originalSize.width * sin(radians)) + abs(originalSize.height * cos(radians))
        let newSize = NSSize(width: rotatedWidth, height: rotatedHeight)

        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byRadians: -radians)
        transform.translateX(by: -originalSize.width / 2, yBy: -originalSize.height / 2)
        transform.concat()

        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)

        rotatedImage.unlockFocus()
        return rotatedImage
    }

    static func saveImage(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            fileType = .jpeg
        case "tif", "tiff":
            fileType = .tiff
        default:
            fileType = .png
        }

        guard let imageData = bitmapImage.representation(using: fileType, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try imageData.write(to: url)
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
