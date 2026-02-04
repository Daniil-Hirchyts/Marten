import AppKit
import SwiftUI

@MainActor
struct RichTextToolbar: View {
    let title: String
    let saveTitle: String
    let canSave: Bool
    let showsFormattingControls: Bool
    let showsTextModifierButtons: Bool
    let showsAppleIntelligenceControl: Bool
    let appleIntelligenceError: String?

    let isBold: Bool
    let isItalic: Bool
    let isUnderline: Bool
    let isStrikethrough: Bool

    let onCancel: () -> Void
    let onSave: () -> Void
    let onCopyPlainText: (() -> Void)?
    let onToggleBold: () -> Void
    let onToggleItalic: () -> Void
    let onToggleUnderline: () -> Void
    let onToggleStrikethrough: () -> Void

    let appleIntelligenceControl: AnyView

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(10)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
                .contentShape(Circle())
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer(minLength: 0)

                Button(action: onSave) {
                    Text(saveTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(canSave ? Color(nsColor: .systemBlue) : Color.white.opacity(0.20))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .contentShape(Capsule())
                .keyboardShortcut(.return, modifiers: .command)
            }

            if showsFormattingControls {
                HStack(spacing: 8) {
                    if showsTextModifierButtons {
                        ItemEditorTextModifierButton(icon: "bold", isActive: isBold, action: onToggleBold)
                        ItemEditorTextModifierButton(icon: "italic", isActive: isItalic, action: onToggleItalic)
                        ItemEditorTextModifierButton(icon: "underline", isActive: isUnderline, action: onToggleUnderline)
                        ItemEditorTextModifierButton(
                            icon: "strikethrough",
                            isActive: isStrikethrough,
                            action: onToggleStrikethrough
                        )
                    }

                    if showsAppleIntelligenceControl {
                        appleIntelligenceControl
                    }

                    Spacer()

                    if let onCopyPlainText {
                        Button(action: onCopyPlainText) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.70))
                        .help("Copy to Clipboard")
                    }
                }
                .padding(.horizontal, 4)

                if let appleIntelligenceError {
                    Text(appleIntelligenceError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
        }
    }
}
