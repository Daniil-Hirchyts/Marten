import AppKit
import MartenCore
import Foundation
import SwiftUI

enum TextFormattingType {
    case bold, italic, underline, strikethrough, clearFormatting
}

extension Notification.Name {
    static let applyTextFormatting = Notification.Name("applyTextFormatting")
    static let textFormattingDidChange = Notification.Name("textFormattingDidChange")
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var attributedText: NSAttributedString?
    @Binding var selection: NSRange?
    let initialAttributedText: NSAttributedString?
    let font: Font
    let writingToolsBehavior: NSWritingToolsBehavior
    let allowedWritingToolsResultOptions: NSWritingToolsResultOptions
    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onStrikethrough: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Make scrollView transparent
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.writingToolsBehavior = writingToolsBehavior
        textView.allowedWritingToolsResultOptions = allowedWritingToolsResultOptions

        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = .labelColor

        let nsFont = NSFont.systemFont(ofSize: 16, weight: .regular)
        textView.font = nsFont

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        if let initialAttributedText, initialAttributedText.length > 0 {
            textView.textStorage?.setAttributedString(initialAttributedText)
            context.coordinator.sanitizeUnsupportedAttributes(in: textView)
            text = initialAttributedText.string
            context.coordinator.attributedText = textView.attributedString()
        } else {
            textView.string = text
            context.coordinator.sanitizeUnsupportedAttributes(in: textView)
            context.coordinator.attributedText = textView.attributedString()
        }

        selection = textView.selectedRange()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        textView.writingToolsBehavior = writingToolsBehavior
        textView.allowedWritingToolsResultOptions = allowedWritingToolsResultOptions
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            selection = selectedRange
        }

        if
            let requestedSelection = context.coordinator.normalizedSelection(
                selection, in: textView),
            requestedSelection != textView.selectedRange()
        {
            textView.setSelectedRange(requestedSelection)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            attributedText: $attributedText,
            selection: $selection,
            onBold: onBold,
            onItalic: onItalic,
            onUnderline: onUnderline,
            onStrikethrough: onStrikethrough
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var attributedText: NSAttributedString?
        @Binding var selection: NSRange?
        let onBold: () -> Void
        let onItalic: () -> Void
        let onUnderline: () -> Void
        let onStrikethrough: () -> Void
        weak var textView: NSTextView?
        private var observer: NSObjectProtocol?
        private var isSanitizingTextChange = false

        init(
            text: Binding<String>,
            attributedText: Binding<NSAttributedString?>,
            selection: Binding<NSRange?>,
            onBold: @escaping () -> Void,
            onItalic: @escaping () -> Void,
            onUnderline: @escaping () -> Void,
            onStrikethrough: @escaping () -> Void
        ) {
            _text = text
            _attributedText = attributedText
            _selection = selection
            self.onBold = onBold
            self.onItalic = onItalic
            self.onUnderline = onUnderline
            self.onStrikethrough = onStrikethrough
            super.init()

            observer = NotificationCenter.default.addObserver(
                forName: .applyTextFormatting,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let type = notification.userInfo?["type"] as? TextFormattingType else {
                    return
                }
                self?.applyFormatting(type)
            }
        }

        deinit {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            sanitizeUnsupportedAttributes(in: textView)
            text = textView.string
            attributedText = textView.attributedString()
            selection = textView.selectedRange()
            updateFormattingState(for: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selection = textView.selectedRange()
            updateFormattingState(for: textView)
        }

        private func updateFormattingState(for textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            
            if selectedRange.length == 0 {
                // At insertion point (or empty document), use typingAttributes
                let font = textView.typingAttributes[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)
                let traits = font.fontDescriptor.symbolicTraits
                let hasUnderline = textView.typingAttributes[.underlineStyle] != nil
                let hasStrikethrough = textView.typingAttributes[.strikethroughStyle] != nil

                NotificationCenter.default.post(
                    name: .textFormattingDidChange,
                    object: nil,
                    userInfo: [
                        "isBold": traits.contains(.bold),
                        "isItalic": traits.contains(.italic),
                        "isUnderline": hasUnderline,
                        "isStrikethrough": hasStrikethrough
                    ]
                )
                return
            }
            
            guard let textStorage = textView.textStorage else { return }

            // Check if any character in selection has formatting
            var isBold = false
            var isItalic = false
            var isUnderline = false
            var isStrikethrough = false

            textStorage.enumerateAttributes(in: selectedRange, options: []) { attributes, _, stop in
                if let font = attributes[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    if traits.contains(.bold) { isBold = true }
                    if traits.contains(.italic) { isItalic = true }
                }
                if attributes[.underlineStyle] != nil { isUnderline = true }
                if attributes[.strikethroughStyle] != nil { isStrikethrough = true }

                // If all are true, we can stop early
                if isBold && isItalic && isUnderline && isStrikethrough {
                    stop.pointee = true
                }
            }

            NotificationCenter.default.post(
                name: .textFormattingDidChange,
                object: nil,
                userInfo: [
                    "isBold": isBold,
                    "isItalic": isItalic,
                    "isUnderline": isUnderline,
                    "isStrikethrough": isStrikethrough
                ]
            )
        }

        func normalizedSelection(_ selection: NSRange?, in textView: NSTextView) -> NSRange? {
            guard let selection, selection.location != NSNotFound, selection.location >= 0 else {
                return nil
            }

            let textLength = (textView.string as NSString).length
            guard selection.location <= textLength else { return nil }

            let remainingLength = textLength - selection.location
            let clampedLength = min(max(0, selection.length), remainingLength)
            return NSRange(location: selection.location, length: clampedLength)
        }

        func sanitizeUnsupportedAttributes(in textView: NSTextView) {
            guard !isSanitizingTextChange, let textStorage = textView.textStorage else { return }
            guard textStorage.length > 0 else { return }

            isSanitizingTextChange = true
            defer { isSanitizingTextChange = false }

            let selectedRange = textView.selectedRange()
            let savedTypingAttributes = textView.typingAttributes
            
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let sanitized = textStorage.removingTextColorAttributes()
            textStorage.setAttributedString(sanitized)

            let baseColor = textView.textColor ?? NSColor.labelColor
            textStorage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
            
            // Restore typing attributes but ensure text color is correct
            var newTypingAttributes = savedTypingAttributes
            newTypingAttributes[.foregroundColor] = baseColor
            textView.typingAttributes = newTypingAttributes
            
            textView.linkTextAttributes = [:]
            textView.setSelectedRange(selectedRange)
            attributedText = textView.attributedString()
            selection = selectedRange
        }

        func applyFormatting(_ type: TextFormattingType) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()

            guard selectedRange.length > 0 else {
                toggleTrait(type)
                return
            }

            guard let textStorage = textView.textStorage else { return }

            // Apply formatting to each character in the selection to handle mixed formatting
            textStorage.enumerateAttributes(in: selectedRange, options: []) { attributes, range, _ in
                // Get the current font at this position or use default
                let currentFont = attributes[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)

                switch type {
                case .bold:
                    let newFont = toggleBoldTrait(in: currentFont)
                    textStorage.addAttribute(.font, value: newFont, range: range)

                case .italic:
                    let newFont = toggleItalicTrait(in: currentFont)
                    textStorage.addAttribute(.font, value: newFont, range: range)

                case .underline:
                    let hasUnderline = attributes[.underlineStyle] != nil
                    if hasUnderline {
                        textStorage.removeAttribute(.underlineStyle, range: range)
                    } else {
                        textStorage.addAttribute(.underlineStyle, value: NSNumber(value: NSUnderlineStyle.single.rawValue), range: range)
                    }

                case .strikethrough:
                    let hasStrikethrough = attributes[.strikethroughStyle] != nil
                    if hasStrikethrough {
                        textStorage.removeAttribute(.strikethroughStyle, range: range)
                    } else {
                        textStorage.addAttribute(.strikethroughStyle, value: NSNumber(value: NSUnderlineStyle.single.rawValue), range: range)
                    }

                case .clearFormatting:
                    // Remove all formatting, set to plain text
                    let plainFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                    textStorage.addAttribute(.font, value: plainFont, range: range)
                    textStorage.removeAttribute(.underlineStyle, range: range)
                    textStorage.removeAttribute(.strikethroughStyle, range: range)
                }
            }

            sanitizeUnsupportedAttributes(in: textView)
            textView.setSelectedRange(selectedRange)
            text = textView.string
            attributedText = textView.attributedString()
            selection = selectedRange
            updateFormattingState(for: textView)
        }

        private func toggleBoldTrait(in font: NSFont) -> NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)

            if isBold && isItalic {
                // Bold + Italic -> Italic
                return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize)
                    ?? NSFont.systemFont(ofSize: font.pointSize)
            } else if isBold {
                // Bold -> Regular
                return NSFont.systemFont(ofSize: font.pointSize, weight: .regular)
            } else if isItalic {
                // Italic -> Bold + Italic
                var newTraits = traits
                newTraits.insert(.bold)
                return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(newTraits), size: font.pointSize)
                    ?? NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
            } else {
                // Regular -> Bold
                return NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
            }
        }

        private func toggleItalicTrait(in font: NSFont) -> NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)

            if isBold && isItalic {
                // Bold + Italic -> Bold
                return NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
            } else if isItalic {
                // Italic -> Regular
                return NSFont.systemFont(ofSize: font.pointSize, weight: .regular)
            } else if isBold {
                // Bold -> Bold + Italic
                var newTraits = traits
                newTraits.insert(.italic)
                return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(newTraits), size: font.pointSize)
                    ?? NSFont.systemFont(ofSize: font.pointSize, weight: .bold)
            } else {
                // Regular -> Italic
                return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize)
                    ?? NSFont.systemFont(ofSize: font.pointSize)
            }
        }

        func toggleTrait(_ type: TextFormattingType) {
            guard let textView = textView else { return }
            var attributes = textView.typingAttributes
            let currentFont = attributes[.font] as? NSFont ?? textView.font ?? NSFont.systemFont(ofSize: 16)

            switch type {
            case .bold:
                let newFont = toggleBoldTrait(in: currentFont)
                attributes[.font] = newFont

            case .italic:
                let newFont = toggleItalicTrait(in: currentFont)
                attributes[.font] = newFont

            case .underline:
                if attributes[.underlineStyle] != nil {
                    attributes.removeValue(forKey: .underlineStyle)
                } else {
                    attributes[.underlineStyle] = NSNumber(value: NSUnderlineStyle.single.rawValue)
                }

            case .strikethrough:
                if attributes[.strikethroughStyle] != nil {
                    attributes.removeValue(forKey: .strikethroughStyle)
                } else {
                    attributes[.strikethroughStyle] = NSNumber(value: NSUnderlineStyle.single.rawValue)
                }

            case .clearFormatting:
                // Reset to plain text
                let plainFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                attributes = [
                    .font: plainFont,
                    .foregroundColor: textView.textColor ?? NSColor.labelColor
                ]
            }

            textView.typingAttributes = attributes
            updateFormattingState(for: textView)
        }
    }
}
