import AppKit
import ClipboardCore
import Foundation
import SwiftUI

enum TextFormattingType {
    case bold, italic, underline, strikethrough
}

extension Notification.Name {
    static let applyTextFormatting = Notification.Name("applyTextFormatting")
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

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.writingToolsBehavior = writingToolsBehavior
        textView.allowedWritingToolsResultOptions = allowedWritingToolsResultOptions

        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = .white

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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selection = textView.selectedRange()
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
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let sanitized = textStorage.removingTextColorAttributes()
            textStorage.setAttributedString(sanitized)

            let baseColor = textView.textColor ?? NSColor.white
            textStorage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
            textView.typingAttributes[.foregroundColor] = baseColor
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
            let selectedText = (textStorage.string as NSString).substring(with: selectedRange)
            var currentFont = textView.font ?? NSFont.systemFont(ofSize: 16)
            let attributedString = NSMutableAttributedString(string: selectedText)

            switch type {
            case .bold:
                if currentFont.fontDescriptor.symbolicTraits.contains(.bold) {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                } else {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
                }
                attributedString.addAttribute(
                    .font, value: currentFont,
                    range: NSRange(location: 0, length: selectedText.count))

            case .italic:
                if currentFont.fontDescriptor.symbolicTraits.contains(.italic) {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize)
                } else {
                    currentFont =
                        NSFont(
                            descriptor: currentFont.fontDescriptor.withSymbolicTraits(.italic),
                            size: currentFont.pointSize) ?? currentFont
                }
                attributedString.addAttribute(
                    .font, value: currentFont,
                    range: NSRange(location: 0, length: selectedText.count))

            case .underline:
                let hasUnderline =
                    textStorage.attribute(
                        .underlineStyle, at: selectedRange.location, effectiveRange: nil) != nil
                if hasUnderline {
                    attributedString.removeAttribute(
                        .underlineStyle, range: NSRange(location: 0, length: selectedText.count))
                } else {
                    attributedString.addAttribute(
                        .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                        range: NSRange(location: 0, length: selectedText.count))
                }
                attributedString.addAttribute(
                    .font, value: currentFont,
                    range: NSRange(location: 0, length: selectedText.count))

            case .strikethrough:
                let hasStrikethrough =
                    textStorage.attribute(
                        .strikethroughStyle, at: selectedRange.location, effectiveRange: nil) != nil
                if hasStrikethrough {
                    attributedString.removeAttribute(
                        .strikethroughStyle, range: NSRange(location: 0, length: selectedText.count)
                    )
                } else {
                    attributedString.addAttribute(
                        .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                        range: NSRange(location: 0, length: selectedText.count))
                }
                attributedString.addAttribute(
                    .font, value: currentFont,
                    range: NSRange(location: 0, length: selectedText.count))
            }

            textStorage.replaceCharacters(in: selectedRange, with: attributedString)
            sanitizeUnsupportedAttributes(in: textView)
            textView.setSelectedRange(selectedRange)
            text = textView.string
            attributedText = textView.attributedString()
            selection = selectedRange
        }

        func toggleTrait(_ type: TextFormattingType) {
            guard let textView = textView else { return }
            var currentFont = textView.font ?? NSFont.systemFont(ofSize: 16)

            switch type {
            case .bold:
                if currentFont.fontDescriptor.symbolicTraits.contains(.bold) {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .regular)
                } else {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize, weight: .bold)
                }
                textView.font = currentFont

            case .italic:
                if currentFont.fontDescriptor.symbolicTraits.contains(.italic) {
                    currentFont = NSFont.systemFont(ofSize: currentFont.pointSize)
                } else {
                    currentFont =
                        NSFont(
                            descriptor: currentFont.fontDescriptor.withSymbolicTraits(.italic),
                            size: currentFont.pointSize) ?? currentFont
                }
                textView.font = currentFont

            case .underline, .strikethrough:
                break
            }
        }
    }
}
