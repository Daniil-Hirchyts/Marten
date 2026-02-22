import MartenCore
import SwiftUI

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
