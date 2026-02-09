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
    static func fileURLPath(from item: ClipItem) -> String? {
        guard let reps = item.representations else { return nil }
        guard let rep = reps.first(where: { $0.kindValue == .fileURL }) else { return nil }
        guard let data = rep.textData, let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func imageFromRepresentations(for item: ClipItem) -> NSImage? {
        guard let representations = item.representations else { return nil }

        for rep in representations {
            let kind = rep.kindValue
            if kind == .png || kind == .jpeg || kind == .tiff {
                if let data = rep.binaryData, let image = NSImage(data: data) {
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
