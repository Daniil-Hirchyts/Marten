import AppKit
import MartenMacServices

extension ItemEditorContentView {
    func handleSave() {
        guard let item else {
            if let attributed = draftAttributedText, attributed.length > 0 {
                var hasFormatting = false
                attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, _, stop in
                    if attrs[.font] != nil {
                        if let font = attrs[.font] as? NSFont {
                            if font.fontDescriptor.symbolicTraits.contains(.bold)
                                || font.fontDescriptor.symbolicTraits.contains(.italic)
                            {
                                hasFormatting = true
                                stop.pointee = true
                            }
                        }
                    }
                    if attrs[.underlineStyle] != nil || attrs[.strikethroughStyle] != nil {
                        hasFormatting = true
                        stop.pointee = true
                    }
                }

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

        default:
            do {
                if item.itemTypeValue == .richText {
                    let attributed =
                        draftAttributedText?.removingTextColorAttributes()
                        ?? NSAttributedString(string: draftText, attributes: [.font: NSFont.systemFont(ofSize: 16)])
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

