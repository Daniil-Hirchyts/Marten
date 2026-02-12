import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct RichTextEditorSheet: View {
    let item: ClipItem
    let appleIntelligence: any AppleIntelligenceTextTransforming
    let onSave: (_ plainText: String, _ rtfData: Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var attributedText: NSAttributedString
    @State private var plainText: String
    @State private var command: RichTextEditorCommand?
    @State private var appleIntelligenceAvailability: AppleIntelligenceAvailability = .unavailable(.modelNotReady)
    @State private var appleIntelligenceTask: Task<Void, Never>?
    @State private var appleIntelligenceError: String?
    @State private var appleIntelligencePreview: AppleIntelligencePreview?
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @ScaledMetric(relativeTo: .subheadline) private var formatButtonWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var formatButtonHeight: CGFloat = 44

    init(
        item: ClipItem,
        appleIntelligence: any AppleIntelligenceTextTransforming,
        onSave: @escaping (_ plainText: String, _ rtfData: Data) -> Void
    ) {
        self.item = item
        self.appleIntelligence = appleIntelligence
        self.onSave = onSave

        let initialAttributed = item.styledTextContentWithoutTextColor
            ?? NSAttributedString(string: item.plainTextContent ?? item.primaryText ?? "")
        _attributedText = State(initialValue: initialAttributed)
        _plainText = State(initialValue: initialAttributed.string)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                if #available(iOS 26, *) {
                    Color.clear.ignoresSafeArea()
                } else {
                    Color(platformColor: .platformSystemGroupedBackground)
                        .ignoresSafeArea()
                }

                // Editor Area
                ScrollView {
                    editor
                        .frame(minHeight: 400)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100) // Space for toolbar
                }

                // Floating Toolbar
                VStack {
                    Spacer()
                    formattingToolbar
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle("Edit Rich Text")
            .richTextSheetTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSave()
                    }
                    .disabled(plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .background {
                // Gradient or Mesh background could go here
                MartenGlassSurface(cornerRadius: 0, padding: 0) {
                    Color.clear
                }
                .ignoresSafeArea()
            }
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
    }

    private var formattingToolbar: some View {
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
            onAppleIntelligence: shouldShowAppleIntelligence ? { action in
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

    @ViewBuilder
    private var editor: some View {
        MartenGlassSurface(cornerRadius: 16, padding: 0) {
            #if canImport(UIKit)
            AttributedTextEditor(
                attributedText: $attributedText,
                plainText: $plainText,
                command: $command,
                isBold: $isBold,
                isItalic: $isItalic,
                isUnderline: $isUnderline,
                isStrikethrough: $isStrikethrough
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            #else
            TextEditor(text: $plainText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .scrollContentBackground(.hidden)
            #endif
        }
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
    
    // MARK: - Apple Intelligence
    
    private func refreshAppleIntelligenceAvailability() async {
        appleIntelligenceAvailability = await appleIntelligence.availability(for: .current)
    }
    
    private func runAppleIntelligenceAction(_ action: AppleIntelligenceTextAction) {
        let sourceText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                appleIntelligenceError = "Apple Intelligence couldn't transform the text right now. Try again."
            }
        }
    }
    
    private func applyAppleIntelligencePreview(_ preview: AppleIntelligencePreview) {
        plainText = preview.transformedText
        #if canImport(UIKit)
        attributedText = NSAttributedString(
            string: preview.transformedText,
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        #else
        attributedText = NSAttributedString(
            string: preview.transformedText,
            attributes: [.font: NSFont.systemFont(ofSize: 16)]
        )
        #endif
        appleIntelligenceError = nil
        appleIntelligencePreview = nil
    }
    
    private func appleIntelligenceErrorMessage(for error: AppleIntelligenceTextTransformationError) -> String {
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
