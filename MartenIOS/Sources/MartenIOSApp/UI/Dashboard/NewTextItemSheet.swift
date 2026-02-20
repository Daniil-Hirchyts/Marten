import MartenCore
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct NewTextItemSheet: View {
    let appleIntelligence: any AppleIntelligenceTextTransforming
    let onSave: (_ plainText: String, _ rtfData: Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var attributedText: NSAttributedString = NSAttributedString()
    @State private var command: RichTextEditorCommand?
    @State private var appleIntelligenceAvailability: AppleIntelligenceAvailability = .unavailable(
        .modelNotReady)
    @State private var appleIntelligenceTask: Task<Void, Never>?
    @State private var appleIntelligenceError: String?
    @State private var appleIntelligencePreview: AppleIntelligencePreview?
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var charCount: Int {
        text.count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            if #available(iOS 26, *) {
                Color.clear.ignoresSafeArea()
            } else {
                Color(platformColor: .platformSystemGroupedBackground)
                    .ignoresSafeArea()
            }

            // Editor Area — full screen
            ScrollView {
                #if canImport(UIKit)
                    AttributedTextEditor(
                        attributedText: $attributedText,
                        plainText: $text,
                        command: $command,
                        isBold: $isBold,
                        isItalic: $isItalic,
                        isUnderline: $isUnderline,
                        isStrikethrough: $isStrikethrough,
                        toolbar: formattingToolbar
                    )
                    .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.7)
                    .padding(.horizontal, 20)
                    .padding(.top, 90)
                    .padding(.bottom, 20)
                #else
                    TextEditor(text: $text)
                        .frame(maxWidth: .infinity, minHeight: 500)
                        .padding(.horizontal, 20)
                        .padding(.top, 90)
                        .padding(.bottom, 100)
                        .scrollContentBackground(.hidden)
                #endif
            }
            // Header overlay with Cancel / Save
            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .padding(.leading, 20)

                    Spacer()

                    Text("New Text")
                        .font(.system(size: 16, weight: .semibold))

                    Spacer()

                    Button("Save") {
                        handleSave()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.trailing, 20)
                    .accessibilityHint("Save the text as a new clip")
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(.regularMaterial)
                Spacer()
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(item: $appleIntelligencePreview) { preview in
            AppleIntelligencePreviewSheet(
                preview: preview,
                onKeep: { appleIntelligencePreview = nil },
                onReplace: { applyAppleIntelligencePreview(preview) }
            )
        }
        .task {
            await refreshAppleIntelligenceAvailability()
        }
    }

    private var formattingToolbar: TextEditorToolbar {
        TextEditorToolbar(
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            isStrikethrough: isStrikethrough,
            shouldShowAppleIntelligence: shouldShowAppleIntelligence,
            isGeneratingAppleIntelligence: isGeneratingAppleIntelligence,
            appleIntelligenceError: appleIntelligenceError,
            onToggleBold: { command = .toggleBold(UUID()) },
            onToggleItalic: { command = .toggleItalic(UUID()) },
            onToggleUnderline: { command = .toggleUnderline(UUID()) },
            onToggleStrikethrough: { command = .toggleStrikethrough(UUID()) },
            onClearFormatting: { command = .clearFormatting(UUID()) },
            onBulletList: { command = .bulletList(UUID()) },
            onNumberedList: { command = .numberedList(UUID()) },
            onHeader1: { command = .header1(UUID()) },
            onHeader2: { command = .header2(UUID()) },
            onAppleIntelligence: shouldShowAppleIntelligence
                ? { action in
                    runAppleIntelligenceAction(action)
                } : nil
        )
    }

    private var shouldShowAppleIntelligence: Bool {
        appleIntelligenceAvailability == .available
    }

    private var isGeneratingAppleIntelligence: Bool {
        appleIntelligenceTask != nil
    }

    private func handleSave() {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }

        #if canImport(UIKit)
            let range = NSRange(location: 0, length: attributedText.length)
            let rtfData =
                (try? attributedText.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )) ?? Data(plain.utf8)
        #else
            let rtfData = Data(plain.utf8)
        #endif

        onSave(plain, rtfData)
    }

    // MARK: - Apple Intelligence

    private func refreshAppleIntelligenceAvailability() async {
        appleIntelligenceAvailability = await appleIntelligence.availability(for: .current)
    }

    private func runAppleIntelligenceAction(_ action: AppleIntelligenceTextAction) {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            appleIntelligenceError = "No text available for Apple Intelligence."
            return
        }

        appleIntelligenceTask?.cancel()
        appleIntelligenceError = nil

        appleIntelligenceTask = Task {
            do {
                let transformed = try await appleIntelligence.transform(
                    sourceText,
                    action: action,
                    locale: .current
                )
                guard !Task.isCancelled else { return }
                appleIntelligencePreview = AppleIntelligencePreview(
                    action: action,
                    originalText: sourceText,
                    transformedText: transformed
                )
                appleIntelligenceTask = nil
            } catch is CancellationError {
                if appleIntelligenceTask?.isCancelled == true {
                    appleIntelligenceTask = nil
                }
            } catch let error as AppleIntelligenceTextTransformationError {
                appleIntelligenceTask = nil
                appleIntelligenceError = appleIntelligenceErrorMessage(for: error)
            } catch {
                appleIntelligenceTask = nil
                appleIntelligenceError =
                    "Apple Intelligence couldn't transform the text right now. Try again."
            }
        }
    }

    private func applyAppleIntelligencePreview(_ preview: AppleIntelligencePreview) {
        text = preview.transformedText
        attributedText = NSAttributedString(
            string: preview.transformedText,
            attributes: [.font: PlatformFont.systemFont(ofSize: 16)]
        )
        appleIntelligenceError = nil
        appleIntelligencePreview = nil
    }

    private func appleIntelligenceErrorMessage(for error: AppleIntelligenceTextTransformationError)
        -> String
    {
        switch error {
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Apple Intelligence isn't available on this device."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to use this feature."
            case .modelNotReady:
                return "Apple Intelligence is still preparing. Try again shortly."
            case .unsupportedLocale:
                return "Apple Intelligence doesn't currently support this locale."
            }
        case .emptyInput:
            return "No text available for Apple Intelligence."
        case .emptyOutput:
            return "Apple Intelligence returned an empty result. Try again."
        case .generationFailed:
            return "Apple Intelligence couldn't transform the text right now. Try again."
        }
    }
}
