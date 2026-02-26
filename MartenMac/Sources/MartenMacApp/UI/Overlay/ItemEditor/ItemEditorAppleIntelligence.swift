import AppKit
import MartenCore
import MartenMacServices
import SwiftUI

extension ItemEditorContentView {
    var appleIntelligenceMenu: some View {
        Menu {
            if supportsCustomAppleIntelligenceActions {
                ForEach(AppleIntelligenceTextAction.allCases, id: \.rawValue) { action in
                    Button(action.title) {
                        runAppleIntelligenceAction(action)
                    }
                    .disabled(!canRunAppleIntelligenceAction(action))
                }

                Divider()
            }

            Button("Open Writing Tools") {
                openSystemWritingTools(selectingFullTextIfNeeded: true)
            }
        } label: {
            ZStack {
                if isGeneratingAppleIntelligence {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.primary.opacity(0.9))
                } else {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.50))
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isGeneratingAppleIntelligence ? Color.primary.opacity(0.20) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isGeneratingAppleIntelligence ? Color.primary.opacity(0.30) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            )
        } primaryAction: {
            openSystemWritingTools(selectingFullTextIfNeeded: true)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Apple Intelligence")
        .accessibilityIdentifier("itemEditor.appleIntelligence.menu")
    }

    var supportsCustomAppleIntelligenceActions: Bool {
        guard let item else { return true }

        switch item.itemTypeValue {
        case .text, .code, .url:
            return true
        default:
            return false
        }
    }

    var shouldShowAppleIntelligenceControl: Bool {
        guard item != nil else {
            return appleIntelligenceAvailability == .available
        }

        if supportsCustomAppleIntelligenceActions {
            return appleIntelligenceAvailability == .available
        }
        return hasRichTextRepresentation
    }

    var isGeneratingAppleIntelligence: Bool {
        appleIntelligenceTask != nil
    }

    var richTextEditorWritingToolsBehavior: NSWritingToolsBehavior {
        guard let item else { return .complete }
        switch item.itemTypeValue {
        case .text, .richText, .url:
            return .complete
        default:
            return .none
        }
    }

    var richTextEditorWritingToolsResultOptions: NSWritingToolsResultOptions {
        guard item != nil else { return [.plainText, .richText, .table, .list] }
        if hasRichTextRepresentation {
            return [.richText, .list, .table, .presentationIntent]
        }
        return .plainText
    }

    var codeSelectionRange: NSRange? {
        ItemEditorHelpers.nsRange(from: codeSelection, in: draftText)
    }

    var currentAIResolvedTarget: ItemEditorAIResolvedTarget {
        let itemType: ItemType = item?.itemTypeValue ?? .text
        return ItemEditorAITextEditing.resolveTarget(
            itemType: itemType,
            draftText: draftText,
            richTextSelection: richTextSelection,
            codeSelection: codeSelectionRange
        )
    }

    func canRunAppleIntelligenceAction(_ action: AppleIntelligenceTextAction) -> Bool {
        guard supportsCustomAppleIntelligenceActions else { return false }
        guard appleIntelligenceAvailability == .available else { return false }
        guard !isGeneratingAppleIntelligence else { return false }
        return !currentAIResolvedTarget.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshAppleIntelligenceAvailability() async {
        appleIntelligenceAvailability = await appleIntelligence.availability(for: .current)
    }

    func runAppleIntelligenceAction(_ action: AppleIntelligenceTextAction) {
        guard supportsCustomAppleIntelligenceActions else { return }

        let target = currentAIResolvedTarget
        guard !target.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appleIntelligenceError = "No text available for Apple Intelligence."
            return
        }

        appleIntelligenceTask?.cancel()
        appleIntelligenceError = nil

        appleIntelligenceTask = Task {
            do {
                let transformed = try await appleIntelligence.transform(
                    target.sourceText,
                    action: action,
                    locale: .current
                )
                guard !Task.isCancelled else { return }
                appleIntelligencePreview = ItemEditorAppleIntelligencePreview(
                    action: action,
                    target: target,
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
                appleIntelligenceError = "Apple Intelligence couldn’t transform the text right now. Try again."
            }
        }
    }

    func openSystemWritingTools(selectingFullTextIfNeeded: Bool = false) {
        if selectingFullTextIfNeeded {
            selectAllTextForWritingToolsIfNeeded()
        }

        DispatchQueue.main.async {
            let didOpen = NSApp.sendAction(
                #selector(NSResponder.showWritingTools(_:)),
                to: nil,
                from: nil
            )
            if !didOpen {
                NSSound.beep()
            }
        }
    }

    func selectAllTextForWritingToolsIfNeeded() {
        let fullTextSelection = NSRange(location: 0, length: (draftText as NSString).length)
        guard fullTextSelection.length > 0 else { return }

        let itemType: ItemType = item?.itemTypeValue ?? .text
        switch itemType {
        case .code:
            if let existingSelection = codeSelectionRange,
                ItemEditorAITextEditing.selectedText(in: draftText, range: existingSelection) != nil
            {
                return
            }

            guard let fullRange = Range(fullTextSelection, in: draftText) else { return }
            codeSelection = TextSelection(range: fullRange)

        case .text, .url, .richText:
            if let existingSelection = richTextSelection,
                ItemEditorAITextEditing.selectedText(in: draftText, range: existingSelection) != nil
            {
                return
            }

            richTextSelection = fullTextSelection

        default:
            break
        }
    }

    func applyAppleIntelligencePreview(_ preview: ItemEditorAppleIntelligencePreview) {
        do {
            draftText = try ItemEditorAITextEditing.applyReplacement(
                to: draftText,
                replacementText: preview.transformedText,
                target: preview.target
            )
            if hasRichTextRepresentation {
                draftAttributedText = NSAttributedString(
                    string: draftText,
                    attributes: [.font: NSFont.systemFont(ofSize: 16)]
                )
            } else {
                draftAttributedText = nil
            }
            appleIntelligenceError = nil
            appleIntelligencePreview = nil
        } catch {
            appleIntelligenceError =
                "Couldn’t apply generated text because the selection changed. Run the action again."
            NSSound.beep()
        }
    }

    @ViewBuilder
    func appleIntelligencePreviewSheet(for preview: ItemEditorAppleIntelligencePreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(preview.action.title) Preview")
                .font(.system(size: 16, weight: .semibold))

            GroupBox("Original") {
                ScrollView {
                    Text(preview.target.sourceText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 110, maxHeight: 170)
            }

            GroupBox("Suggestion") {
                ScrollView {
                    Text(preview.transformedText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 110, maxHeight: 200)
            }

            HStack {
                Button("Keep Original") {
                    appleIntelligencePreview = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Replace Text") {
                    applyAppleIntelligencePreview(preview)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560)
    }

    func appleIntelligenceErrorMessage(for error: AppleIntelligenceTextTransformationError) -> String {
        switch error {
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Apple Intelligence isn’t available on this Mac."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use this feature."
            case .modelNotReady:
                return "Apple Intelligence is still preparing. Try again shortly."
            case .unsupportedLocale:
                return "Apple Intelligence doesn’t currently support this locale."
            }
        case .emptyInput:
            return "No text available for Apple Intelligence."
        case .emptyOutput:
            return "Apple Intelligence returned an empty result. Try again."
        case .generationFailed:
            return "Apple Intelligence couldn’t transform the text right now. Try again."
        }
    }

    private var hasRichTextRepresentation: Bool {
        if let item, item.styledTextContentWithoutTextColor != nil {
            return true
        }

        if let draftAttributedText {
            return ItemEditorHelpers.hasRichFormatting(draftAttributedText)
        }

        return false
    }
}
