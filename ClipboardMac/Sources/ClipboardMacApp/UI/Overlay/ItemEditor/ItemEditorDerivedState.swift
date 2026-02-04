import ClipboardCore
import SwiftUI

extension ItemEditorContentView {
    var titleText: String {
        mode == .createNew ? "New Text Item" : editorTitle
    }

    var saveTitle: String {
        mode == .createNew ? "Save to Clipboard" : "Save"
    }

    var supportsCopyButton: Bool {
        guard let item else { return true }
        return item.itemTypeValue != .code
    }

    var showsFormattingControls: Bool {
        mode == .createNew ? true : supportsTextEditing
    }

    var showsTextModifierButtons: Bool {
        guard let item else { return true }
        return item.itemTypeValue != .code
    }

    var canSave: Bool {
        guard let item else {
            return !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        switch item.itemTypeValue {
        case .file, .image:
            return !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return supportsTextEditing
        }
    }

    var editorTitle: String {
        guard let item else { return "New Text Item" }
        switch item.itemTypeValue {
        case .code:
            return "Edit Code"
        case .url:
            return "Edit URL"
        case .color:
            return "Edit Color"
        case .image:
            return "Edit Image"
        case .file:
            return "Edit File"
        default:
            return "Edit Text"
        }
    }

    var supportsTextEditing: Bool {
        guard let item else { return true }
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color:
            return true
        default:
            return false
        }
    }

    var supportsEditing: Bool {
        guard let item else { return true }
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color, .file, .image:
            return true
        default:
            return false
        }
    }

    var editorFont: Font {
        if let item {
            return item.itemTypeValue == .code
                ? .system(size: 16, weight: .regular, design: .monospaced)
                : .system(size: 16)
        }
        return .system(size: 16)
    }

    var originalFileName: String {
        guard let item else { return "Untitled" }
        if item.itemTypeValue == .file, let filePath = item.primaryText {
            return URL(fileURLWithPath: filePath).lastPathComponent
        } else if item.itemTypeValue == .image {
            if let path = ItemEditorHelpers.fileURLPath(from: item) {
                return URL(fileURLWithPath: path).lastPathComponent
            } else {
                return "image.png"
            }
        }
        return "Untitled"
    }
}

