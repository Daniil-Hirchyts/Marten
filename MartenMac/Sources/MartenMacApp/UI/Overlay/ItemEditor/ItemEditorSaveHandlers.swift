import AppKit
import MartenMacServices

extension ItemEditorContentView {
    func handleSave() {
        guard let item else {
            if let attributed = draftAttributedText, attributed.length > 0 {
                let hasFormatting = ItemEditorHelpers.hasRichFormatting(attributed)

                if hasFormatting {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()

                    if let rtfData = attributed.clipboardData(for: .rtf) {
                        pasteboard.setData(rtfData, forType: .rtf)
                    }
                    pasteboard.setString(draftText, forType: .string)

                    onSave(draftText)
                    return
                }
            }

            onSave(draftText)
            return
        }

        switch item.itemTypeValue {
        case .image:
            let totalRotation = rotationAngle.degrees.truncatingRemainder(dividingBy: 360)
            if let original = originalImage, totalRotation != 0 {
                let finalImage = ItemEditorHelpers.applyRotation(to: original, degrees: totalRotation)
                if let imageData = ItemEditorHelpers.imageDataPNG(from: finalImage) {
                    do {
                        try clipItemEditor.updateImageData(objectID: item.objectID, imageData: imageData)
                    } catch {
                        NSSound.beep()
                    }
                }
            }
            if fileName != originalFileName {
                do {
                    try clipItemEditor.renameItem(objectID: item.objectID, title: fileName)
                } catch {
                    NSSound.beep()
                }
            }
            onSave(fileName)

        case .file:
            if fileName != originalFileName {
                do {
                    try clipItemEditor.updateFileName(objectID: item.objectID, newFileName: fileName)
                } catch {
                    NSSound.beep()
                }
            }
            onSave(fileName)

        case .color:
            let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                do {
                    try clipItemEditor.deleteItem(objectID: item.objectID)
                } catch {
                    NSSound.beep()
                }
                return
            }

            do {
                _ = try clipItemEditor.updateTextItem(objectID: item.objectID, newText: draftText)
            } catch {
                NSSound.beep()
            }
            onSave(draftText)

        default:
            do {
                let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    try clipItemEditor.deleteItem(objectID: item.objectID)
                    return
                }

                let attributed =
                    draftAttributedText?.removingTextColorAttributes()
                    ?? NSAttributedString(
                        string: draftText,
                        attributes: [.font: NSFont.systemFont(ofSize: 16)]
                    )

                let shouldPersistRichText = item.styledTextContentWithoutTextColor != nil
                    || ItemEditorHelpers.hasRichFormatting(attributed)

                if shouldPersistRichText {
                    guard let rtfData = attributed.clipboardData(for: .rtf) else {
                        NSSound.beep()
                        return
                    }
                    _ = try clipItemEditor.updateRichTextItem(
                        objectID: item.objectID,
                        newText: attributed.string,
                        rtfData: rtfData
                    )
                } else {
                    _ = try clipItemEditor.updateTextItem(objectID: item.objectID, newText: draftText)
                }
            } catch {
                NSSound.beep()
                return
            }
            onSave(draftText)
        }
    }
}
