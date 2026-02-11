import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

private enum RichTextEditorCommand: Equatable {
    case toggleBold(UUID)
    case toggleItalic(UUID)
    case bulletList(UUID)
    case numberedList(UUID)
    case header1(UUID)
    case header2(UUID)
}

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

struct RichTextEditorSheet: View {
    let item: ClipItem
    let onSave: (_ plainText: String, _ rtfData: Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var attributedText: NSAttributedString
    @State private var plainText: String
    @State private var command: RichTextEditorCommand?
    @ScaledMetric(relativeTo: .subheadline) private var formatButtonWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .subheadline) private var formatButtonHeight: CGFloat = 30

    init(item: ClipItem, onSave: @escaping (_ plainText: String, _ rtfData: Data) -> Void) {
        self.item = item
        self.onSave = onSave

        let initialAttributed = item.styledTextContentWithoutTextColor
            ?? NSAttributedString(string: item.plainTextContent ?? item.primaryText ?? "")
        _attributedText = State(initialValue: initialAttributed)
        _plainText = State(initialValue: initialAttributed.string)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                toolbar
                editor
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .navigationTitle("Edit Rich Text")
            .richTextSheetTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSave()
                    }
                    .disabled(plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var toolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                formatButton("B", accessibilityLabel: "Bold", action: { command = .toggleBold(UUID()) })
                formatButton("I", accessibilityLabel: "Italic", action: { command = .toggleItalic(UUID()) })
                formatIconButton("list.bullet", accessibilityLabel: "Bullet list", action: { command = .bulletList(UUID()) })
                formatIconButton("list.number", accessibilityLabel: "Numbered list", action: { command = .numberedList(UUID()) })
                formatButton("H1", accessibilityLabel: "Heading 1", action: { command = .header1(UUID()) })
                formatButton("H2", accessibilityLabel: "Heading 2", action: { command = .header2(UUID()) })
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var editor: some View {
        #if canImport(UIKit)
        AttributedTextEditor(
            attributedText: $attributedText,
            plainText: $plainText,
            command: $command
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        #else
        TextEditor(text: $plainText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
        #endif
    }

    private func formatButton(_ title: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .frame(width: formatButtonWidth, height: formatButtonHeight)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
    }

    private func formatIconButton(_ systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: formatButtonWidth, height: formatButtonHeight)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
    }

    private func handleSave() {
        let plain = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }

        let range = NSRange(location: 0, length: attributedText.length)
        let rtfData =
            (try? attributedText.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )) ?? Data(plain.utf8)

        onSave(plain, rtfData)
        dismiss()
    }
}

#if !os(iOS)
private extension View {
    func richTextSheetTitleDisplayMode() -> some View { self }
}
#else
private extension View {
    func richTextSheetTitleDisplayMode() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }
}
#endif

#if canImport(UIKit)
private struct AttributedTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var command: RichTextEditorCommand?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.attributedText = attributedText
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.alwaysBounceVertical = true
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if !textView.attributedText.isEqual(to: attributedText) {
            textView.attributedText = attributedText
        }

        if let command, command != context.coordinator.lastCommand {
            context.coordinator.lastCommand = command
            context.coordinator.apply(command)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            attributedText: $attributedText,
            plainText: $plainText
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSAttributedString
        @Binding var plainText: String
        weak var textView: UITextView?
        var lastCommand: RichTextEditorCommand?

        init(
            attributedText: Binding<NSAttributedString>,
            plainText: Binding<String>
        ) {
            _attributedText = attributedText
            _plainText = plainText
        }

        func textViewDidChange(_ textView: UITextView) {
            syncBindings(from: textView)
        }

        func apply(_ command: RichTextEditorCommand) {
            guard let textView else { return }

            switch command {
            case .toggleBold:
                toggleFontTrait(.traitBold, in: textView)
            case .toggleItalic:
                toggleFontTrait(.traitItalic, in: textView)
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
