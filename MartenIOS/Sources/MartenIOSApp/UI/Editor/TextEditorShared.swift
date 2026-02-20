import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared Command Types

enum RichTextEditorCommand: Equatable {
    case toggleBold(UUID)
    case toggleItalic(UUID)
    case toggleUnderline(UUID)
    case toggleStrikethrough(UUID)
    case clearFormatting(UUID)
    case bulletList(UUID)
    case numberedList(UUID)
    case header1(UUID)
    case header2(UUID)
}

// MARK: - Shared Formatting Transforms

enum RichTextFormattingTransforms {
    static func applyBulletList(to text: String, prefix: String = "• ") -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let stringLine = String(line)
                if stringLine.isEmpty || stringLine.hasPrefix(prefix) {
                    return stringLine
                }
                return prefix + stringLine
            }
            .joined(separator: "\n")
    }

    static func applyNumberedList(to text: String, startAt: Int = 1) -> String {
        var counter = max(1, startAt)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let stringLine = String(line)
                guard !stringLine.isEmpty else { return stringLine }
                defer { counter += 1 }
                return "\(counter). \(stringLine)"
            }
            .joined(separator: "\n")
    }
}

// MARK: - Shared Apple Intelligence Preview

struct AppleIntelligencePreview: Identifiable {
    let id = UUID()
    let action: AppleIntelligenceTextAction
    let originalText: String
    let transformedText: String
}

// MARK: - Shared Toolbar

struct TextEditorToolbar: View {
    let isBold: Bool
    let isItalic: Bool
    let isUnderline: Bool
    let isStrikethrough: Bool
    let shouldShowAppleIntelligence: Bool
    let isGeneratingAppleIntelligence: Bool
    let appleIntelligenceError: String?
    
    let onToggleBold: () -> Void
    let onToggleItalic: () -> Void
    let onToggleUnderline: () -> Void
    let onToggleStrikethrough: () -> Void
    let onClearFormatting: () -> Void
    let onBulletList: () -> Void
    let onNumberedList: () -> Void
    let onHeader1: () -> Void
    let onHeader2: () -> Void
    let onAppleIntelligence: ((AppleIntelligenceTextAction) -> Void)?
    
    var body: some View {
        VStack(spacing: 6) {
            if let error = appleIntelligenceError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.1))
                    )
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                formatStateButton("B", isActive: isBold, accessibilityLabel: "Bold", action: onToggleBold)
                Spacer(minLength: 0)
                formatStateButton("I", isActive: isItalic, accessibilityLabel: "Italic", action: onToggleItalic)
                Spacer(minLength: 0)
                formatStateButton("U", isActive: isUnderline, accessibilityLabel: "Underline", action: onToggleUnderline)
                Spacer(minLength: 0)
                formatStateIconButton("strikethrough", isActive: isStrikethrough, accessibilityLabel: "Strikethrough", action: onToggleStrikethrough)
                Spacer(minLength: 0)
                formatIconButton("list.bullet", accessibilityLabel: "Bullet list", action: onBulletList)
                Spacer(minLength: 0)
                formatIconButton("list.number", accessibilityLabel: "Numbered list", action: onNumberedList)
                Spacer(minLength: 0)
                formatButton("H1", accessibilityLabel: "Heading 1", action: onHeader1)
                Spacer(minLength: 0)
                formatButton("H2", accessibilityLabel: "Heading 2", action: onHeader2)
                Spacer(minLength: 0)
                formatIconButton("textformat.slash", accessibilityLabel: "Clear formatting", action: onClearFormatting)
                Spacer(minLength: 0)

                if shouldShowAppleIntelligence, let onAppleIntelligence {
                    appleIntelligenceButton(onAction: onAppleIntelligence)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.clear))
            #if os(iOS)
            .glassEffect(.regular.interactive(), in: .capsule)
            #else
            .background(.ultraThinMaterial, in: .capsule)
            #endif
            .padding(.horizontal, 16)
        }
    }

    private func formatButton(_ title: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatStateButton(_ title: String, isActive: Bool, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatIconButton(_ systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatStateIconButton(_ systemImage: String, isActive: Bool, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func appleIntelligenceButton(onAction: @escaping (AppleIntelligenceTextAction) -> Void) -> some View {
        Menu {
            ForEach(AppleIntelligenceTextAction.allCases, id: \.rawValue) { action in
                Button(action.title) {
                    onAction(action)
                }
                .disabled(isGeneratingAppleIntelligence)
            }
        } label: {
            ZStack {
                if isGeneratingAppleIntelligence {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Shared Apple Intelligence Preview Sheet

struct AppleIntelligencePreviewSheet: View {
    let preview: AppleIntelligencePreview
    let onKeep: () -> Void
    let onReplace: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Text(preview.originalText)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(platformColor: .platformSecondarySystemGroupedBackground))
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestion")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Text(preview.transformedText)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }
                }
                .padding(16)
            }
            .navigationTitle(preview.action.title + " Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Original", action: onKeep)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace Text", action: onReplace)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Shared Attributed Text Editor

#if canImport(UIKit)
struct AttributedTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var command: RichTextEditorCommand?
    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderline: Bool
    @Binding var isStrikethrough: Bool
    var toolbar: TextEditorToolbar

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.alwaysBounceVertical = true
        textView.delegate = context.coordinator

        // Ensure typed text always uses adaptive label color
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]

        // Apply attributed text after configuring textColor so the
        // fallback foreground from the text storage is correct
        if attributedText.length > 0 {
            textView.attributedText = strippingForegroundColor(attributedText)
        }

        // Enable Writing Tools on iOS 18+
        if #available(iOS 18.0, *) {
            textView.writingToolsBehavior = .complete
        }

        // Attach toolbar as keyboard accessory view
        let hostingController = UIHostingController(rootView: toolbar)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(
            x: 0, y: 0,
            width: UIScreen.main.bounds.width,
            height: 56
        )
        hostingController.view.autoresizingMask = [.flexibleWidth]
        textView.inputAccessoryView = hostingController.view
        context.coordinator.toolbarHostingController = hostingController

        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if !textView.attributedText.isEqual(to: attributedText) {
            textView.attributedText = strippingForegroundColor(attributedText)
            // Reassert textColor so the view renders label color in dark mode
            textView.textColor = .label
        }

        if let command, command != context.coordinator.lastCommand {
            context.coordinator.lastCommand = command
            context.coordinator.apply(command)
        }

        // Keep toolbar in sync with formatting state
        context.coordinator.toolbarHostingController?.rootView = toolbar
    }

    /// Returns a copy of the attributed string with `.foregroundColor` set to the
    /// adaptive `UIColor.label` on every range, so text adapts to dark / light mode.
    /// UITextView ignores `textColor` for attributed text — the attribute in the string
    /// itself is what governs the rendered color.
    private func strippingForegroundColor(_ source: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        return mutable
    }


    func makeCoordinator() -> Coordinator {
        Coordinator(
            attributedText: $attributedText,
            plainText: $plainText,
            isBold: $isBold,
            isItalic: $isItalic,
            isUnderline: $isUnderline,
            isStrikethrough: $isStrikethrough
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSAttributedString
        @Binding var plainText: String
        @Binding var isBold: Bool
        @Binding var isItalic: Bool
        @Binding var isUnderline: Bool
        @Binding var isStrikethrough: Bool
        weak var textView: UITextView?
        var lastCommand: RichTextEditorCommand?
        var toolbarHostingController: UIHostingController<TextEditorToolbar>?

        init(
            attributedText: Binding<NSAttributedString>,
            plainText: Binding<String>,
            isBold: Binding<Bool>,
            isItalic: Binding<Bool>,
            isUnderline: Binding<Bool>,
            isStrikethrough: Binding<Bool>
        ) {
            _attributedText = attributedText
            _plainText = plainText
            _isBold = isBold
            _isItalic = isItalic
            _isUnderline = isUnderline
            _isStrikethrough = isStrikethrough
        }

        func textViewDidChange(_ textView: UITextView) {
            syncBindings(from: textView)
            updateFormattingState(for: textView)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            updateFormattingState(for: textView)
        }
        
        private func updateFormattingState(for textView: UITextView) {
            let selectedRange = textView.selectedRange
            
            if selectedRange.length == 0 {
                // At insertion point, use typingAttributes
                let font = textView.typingAttributes[.font] as? UIFont ?? textView.font ?? .systemFont(ofSize: 16)
                let traits = font.fontDescriptor.symbolicTraits
                let hasUnderline = textView.typingAttributes[.underlineStyle] != nil
                let hasStrikethrough = textView.typingAttributes[.strikethroughStyle] != nil
                
                isBold = traits.contains(.traitBold)
                isItalic = traits.contains(.traitItalic)
                isUnderline = hasUnderline
                isStrikethrough = hasStrikethrough
                return
            }
            
            // Check if any character in selection has formatting
            var hasBold = false
            var hasItalic = false
            var hasUnderlineAttr = false
            var hasStrikethroughAttr = false
            
            textView.attributedText.enumerateAttributes(in: selectedRange, options: []) { attributes, _, stop in
                if let font = attributes[.font] as? UIFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    if traits.contains(.traitBold) { hasBold = true }
                    if traits.contains(.traitItalic) { hasItalic = true }
                }
                if attributes[.underlineStyle] != nil { hasUnderlineAttr = true }
                if attributes[.strikethroughStyle] != nil { hasStrikethroughAttr = true }
                
                if hasBold && hasItalic && hasUnderlineAttr && hasStrikethroughAttr {
                    stop.pointee = true
                }
            }
            
            isBold = hasBold
            isItalic = hasItalic
            isUnderline = hasUnderlineAttr
            isStrikethrough = hasStrikethroughAttr
        }

        func apply(_ command: RichTextEditorCommand) {
            guard let textView else { return }

            switch command {
            case .toggleBold:
                toggleFontTrait(.traitBold, in: textView)
            case .toggleItalic:
                toggleFontTrait(.traitItalic, in: textView)
            case .toggleUnderline:
                toggleAttribute(.underlineStyle, in: textView)
            case .toggleStrikethrough:
                toggleAttribute(.strikethroughStyle, in: textView)
            case .clearFormatting:
                clearFormatting(in: textView)
            case .bulletList:
                applyListPrefix("• ", in: textView)
            case .numberedList:
                applyNumberedList(in: textView)
            case .header1:
                applyHeader(fontSize: 24, in: textView)
            case .header2:
                applyHeader(fontSize: 20, in: textView)
            }

            syncBindings(from: textView)
            updateFormattingState(for: textView)
        }

        private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, in textView: UITextView) {
            let range = textView.selectedRange
            let storage = textView.textStorage

            if range.length > 0 {
                storage.beginEditing()
                storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                    let current = (value as? UIFont) ?? textView.font ?? .systemFont(ofSize: 16)
                    var traits = current.fontDescriptor.symbolicTraits
                    if traits.contains(trait) {
                        traits.remove(trait)
                    } else {
                        traits.insert(trait)
                    }

                    let descriptor =
                        current.fontDescriptor.withSymbolicTraits(traits) ?? current.fontDescriptor
                    let updated = UIFont(descriptor: descriptor, size: current.pointSize)
                    storage.addAttribute(.font, value: updated, range: subrange)
                }
                storage.endEditing()
            } else {
                var typing = textView.typingAttributes
                let current = (typing[.font] as? UIFont) ?? textView.font ?? .systemFont(ofSize: 16)
                var traits = current.fontDescriptor.symbolicTraits
                if traits.contains(trait) {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }
                let descriptor = current.fontDescriptor.withSymbolicTraits(traits) ?? current.fontDescriptor
                typing[.font] = UIFont(descriptor: descriptor, size: current.pointSize)
                textView.typingAttributes = typing
            }
        }
        
        private func toggleAttribute(_ attribute: NSAttributedString.Key, in textView: UITextView) {
            let range = textView.selectedRange
            let storage = textView.textStorage
            
            if range.length > 0 {
                storage.beginEditing()
                storage.enumerateAttribute(attribute, in: range) { value, subrange, _ in
                    if value != nil {
                        storage.removeAttribute(attribute, range: subrange)
                    } else {
                        storage.addAttribute(attribute, value: NSNumber(value: NSUnderlineStyle.single.rawValue), range: subrange)
                    }
                }
                storage.endEditing()
            } else {
                var typing = textView.typingAttributes
                if typing[attribute] != nil {
                    typing.removeValue(forKey: attribute)
                } else {
                    typing[attribute] = NSNumber(value: NSUnderlineStyle.single.rawValue)
                }
                textView.typingAttributes = typing
            }
        }
        
        private func clearFormatting(in textView: UITextView) {
            let range = textView.selectedRange
            let storage = textView.textStorage
            
            if range.length > 0 {
                storage.beginEditing()
                let plainFont = UIFont.systemFont(ofSize: 16, weight: .regular)
                storage.addAttribute(.font, value: plainFont, range: range)
                storage.removeAttribute(.underlineStyle, range: range)
                storage.removeAttribute(.strikethroughStyle, range: range)
                storage.endEditing()
            } else {
                let plainFont = UIFont.systemFont(ofSize: 16, weight: .regular)
                textView.typingAttributes = [
                    .font: plainFont,
                    .foregroundColor: UIColor.label
                ]
            }
        }

        private func applyHeader(fontSize: CGFloat, in textView: UITextView) {
            let nsText = textView.text as NSString
            let selected = textView.selectedRange
            let paragraphRange = nsText.paragraphRange(for: selected)
            let storage = textView.textStorage

            let headerFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            storage.addAttribute(.font, value: headerFont, range: paragraphRange)
        }

        private func applyListPrefix(_ prefix: String, in textView: UITextView) {
            let text = textView.text as NSString
            let selected = textView.selectedRange
            let lineRange = text.lineRange(for: selected)
            let selectedText = text.substring(with: lineRange)
            let transformed = RichTextFormattingTransforms.applyBulletList(
                to: selectedText,
                prefix: prefix
            )

            textView.textStorage.replaceCharacters(in: lineRange, with: transformed)
            textView.selectedRange = NSRange(location: lineRange.location, length: transformed.count)
        }

        private func applyNumberedList(in textView: UITextView) {
            let text = textView.text as NSString
            let selected = textView.selectedRange
            let lineRange = text.lineRange(for: selected)
            let selectedText = text.substring(with: lineRange)
            let transformed = RichTextFormattingTransforms.applyNumberedList(to: selectedText)

            textView.textStorage.replaceCharacters(in: lineRange, with: transformed)
            textView.selectedRange = NSRange(location: lineRange.location, length: transformed.count)
        }

        private func syncBindings(from textView: UITextView) {
            attributedText = textView.attributedText
            plainText = textView.text
        }
    }
}
#endif
