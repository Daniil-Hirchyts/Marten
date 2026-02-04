import AppKit
import ClipboardCore
import SwiftUI

@MainActor
struct TextEditorView: View {
    let itemType: ItemType
    let initialAttributedText: NSAttributedString?
    let font: Font
    let writingToolsBehavior: NSWritingToolsBehavior
    let allowedWritingToolsResultOptions: NSWritingToolsResultOptions
    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onStrikethrough: () -> Void

    @Binding var text: String
    @Binding var attributedText: NSAttributedString?
    @Binding var richTextSelection: NSRange?
    @Binding var codeSelection: TextSelection?

    @FocusState.Binding var isFocused: Bool

    var body: some View {
        switch itemType {
        case .text, .richText, .url, .color:
            RichTextEditor(
                text: $text,
                attributedText: $attributedText,
                selection: $richTextSelection,
                initialAttributedText: itemType == .richText ? initialAttributedText : nil,
                font: font,
                writingToolsBehavior: writingToolsBehavior,
                allowedWritingToolsResultOptions: allowedWritingToolsResultOptions,
                onBold: onBold,
                onItalic: onItalic,
                onUnderline: onUnderline,
                onStrikethrough: onStrikethrough
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id("richTextEditor")

        case .code:
            TextEditor(text: $text, selection: $codeSelection)
                .font(font)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .writingToolsBehavior(.complete)
                .focused($isFocused)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.yellow.opacity(0.8))

                Text("Editing isn't supported for this item type")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }
}

