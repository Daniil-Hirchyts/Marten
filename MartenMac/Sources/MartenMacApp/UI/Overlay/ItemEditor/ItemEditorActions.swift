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
        guard let item, let url = ItemEditorHelpers.exportedFileURL(from: item) else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }

    func openFile() {
        guard let item, let url = ItemEditorHelpers.exportedFileURL(from: item) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyFilePath() {
        guard let item else { return }
        if let path = ItemEditorHelpers.exportedFileURL(from: item)?.path {
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
