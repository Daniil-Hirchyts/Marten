import AppKit
import MartenCore
import OSLog
import SwiftUI

extension ItemEditorContentView {
    func handleAppear() {
        isFocused = true

        if let item {
            if item.itemTypeValue == .image {
                loadImageAsync(item: item)
            } else if item.itemTypeValue == .file {
                loadFileIcon(item: item)
            }

            if supportsCustomAppleIntelligenceActions {
                Task { await refreshAppleIntelligenceAvailability() }
            }
        } else {
            Task { await refreshAppleIntelligenceAvailability() }
        }
    }

    func handleDisappear() {
        appleIntelligenceTask?.cancel()
        appleIntelligenceTask = nil
    }

    func toggleFormatting(_ type: TextFormattingType) {
        // Just apply formatting - state will be updated via notification
        applyFormatting(type)
    }

    func copyPlainTextToMarten() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draftText, forType: .string)
    }

    func loadImageAsync(item: ClipItem) {
        if let thumbnailPath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !thumbnailPath.isEmpty,
            let image = NSImage(contentsOfFile: thumbnailPath)
        {
            loadedImage = image
            originalImage = image
            return
        }

        Task.detached(priority: .userInitiated) {
            let image = ItemEditorHelpers.imageFromRepresentations(for: item)
            await MainActor.run {
                loadedImage = image
                originalImage = image
            }
        }
    }

    func loadFileIcon(item: ClipItem) {
        guard let path = ItemEditorHelpers.fileURLPath(from: item) else {
            loadedFileIcon = nil
            return
        }
        loadedFileIcon = NSWorkspace.shared.icon(forFile: path)
    }

    func revealInFinder() {
        guard let filePath = item?.primaryText else { return }
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
    }

    func openFile() {
        guard let filePath = item?.primaryText else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
    }

    func copyFilePath() {
        guard let item else { return }
        if let path = ItemEditorHelpers.fileURLPath(from: item) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
        }
    }

    func rotateImage(direction: RotationDirection) {
        let rotationDegrees: Double = direction == .left ? -90 : 90
        withAnimation(.easeInOut(duration: 0.3)) {
            rotationAngle += Angle(degrees: rotationDegrees)
        }
    }

    func copyImageToMarten() {
        guard let image = originalImage else {
            NSSound.beep()
            return
        }

        let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
        let finalImage = ItemEditorHelpers.applyRotation(to: image, degrees: totalRotation)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }

    func saveImageToFile() {
        guard let image = originalImage else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg, .tiff]
        savePanel.nameFieldStringValue = fileName
        savePanel.canCreateDirectories = true
        savePanel.title = "Save Image"

        let response = savePanel.runModal()

        if response == .OK, let url = savePanel.url {
            let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
            let finalImage = ItemEditorHelpers.applyRotation(to: image, degrees: totalRotation)
            do {
                try ItemEditorHelpers.saveImage(finalImage, to: url)
            } catch {
                NSSound.beep()
                Logger.ui.error("Failed to save image: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}

