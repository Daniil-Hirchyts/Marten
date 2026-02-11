import AppKit
import MartenCore
import Foundation
import LinkPresentation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension OverlayItemPreview {
    func openURLInExternalBrowser() {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.open(url)
    }

    func shareItem() {
        let items = shareItems
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }

        let picker = NSSharingServicePicker(items: items)
        guard
            let window = NSApp.keyWindow ?? NSApp.mainWindow,
            let contentView = window.contentView
        else {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = contentView.convert(windowPoint, from: nil)
        let shareRect = NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1)
        picker.show(relativeTo: shareRect, of: contentView, preferredEdge: .maxY)
    }

    var shareItems: [Any] {
        var items: [Any] = []

        switch item.itemTypeValue {
        case .file:
            if let filePath {
                items.append(URL(fileURLWithPath: filePath))
            }
        case .url:
            if let normalizedPrimaryURL {
                items.append(normalizedPrimaryURL)
            }
        case .image:
            if let image {
                items.append(image)
            } else if
                let path =
                    fullResolutionImagePathFromRepresentations()
                    ?? filePathFromRepresentations()
                    ?? nonEmptyText(item.thumbnailPath)
            {
                items.append(URL(fileURLWithPath: path))
            }
        case .mixed:
            if let filePath = filePathFromRepresentations() {
                items.append(URL(fileURLWithPath: filePath))
            }
            if let normalizedPrimaryURL {
                items.append(normalizedPrimaryURL)
            }
        default:
            break
        }

        if let text = nonEmptyText(item.plainTextContent ?? item.primaryText) {
            items.append(text)
        }

        return items
    }

    func rotateImage(direction: ImagePreview.RotationDirection) {
        guard let currentImage = image else {
            NSSound.beep()
            return
        }

        let rotationDegrees: Double = direction == .left ? -90 : 90
        let rotatedImage = rotateNSImage(currentImage, degrees: rotationDegrees)

        guard let imageData = imageDataFrom(rotatedImage) else {
            NSSound.beep()
            return
        }

        do {
            try clipItemEditor.updateImageData(objectID: item.objectID, imageData: imageData)
            image = rotatedImage
        } catch {
            NSSound.beep()
            Logger.ui.error(
                "Failed to save rotated image: \(error.localizedDescription, privacy: .private)")
        }
    }

    func imageDataFrom(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }

    func rotateNSImage(_ image: NSImage, degrees: Double) -> NSImage {
        let radians = CGFloat(degrees * .pi / 180.0)

        let originalSize = image.size
        let rotatedWidth =
            abs(originalSize.width * CoreGraphics.cos(radians))
            + abs(originalSize.height * CoreGraphics.sin(radians))
        let rotatedHeight =
            abs(originalSize.width * CoreGraphics.sin(radians))
            + abs(originalSize.height * CoreGraphics.cos(radians))
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

    func saveImageAs() {
        guard let image else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Image"
        savePanel.nameFieldStringValue = imageFileName ?? "image.png"
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.png, .jpeg, .tiff]
        savePanel.allowsOtherFileTypes = false

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            saveImage(image, to: url)
        }
    }

    func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        else {
            NSSound.beep()
            return
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
            NSSound.beep()
            return
        }

        do {
            try imageData.write(to: url)
        } catch {
            NSSound.beep()
            Logger.ui.error(
                "Failed to save image: \(error.localizedDescription, privacy: .private)")
        }
    }

    func saveFileAs() {
        guard let sourcePath = filePath else {
            NSSound.beep()
            return
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)

        let savePanel = NSSavePanel()
        savePanel.title = "Save File"
        savePanel.nameFieldStringValue = fileDisplayName
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                NSSound.beep()
                Logger.ui.error(
                    "Failed to save file: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
