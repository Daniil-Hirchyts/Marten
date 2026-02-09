import AppKit
@preconcurrency import MartenCore
import SwiftUI

struct OverlayItemEditor: View {
    let item: ClipItem
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var draftText: String
    @FocusState private var isFocused: Bool

    init(item: ClipItem, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _draftText = State(initialValue: item.primaryText ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            VStack(spacing: 16) {
                toolbar
                editorSurface
                footer
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .adaptiveGlassBackground(
                shape: .roundedRectangle(cornerRadius: 34),
                isSelected: true,
                isHovering: false
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .padding(8)
        }
        .onAppear {
            isFocused = true
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )

            Spacer(minLength: 0)

            HStack(spacing: 18) {
                Image(systemName: "bold")
                Image(systemName: "italic")
                Image(systemName: "underline")
                Image(systemName: "strikethrough")
                Image(systemName: "arrow.uturn.left")
                Image(systemName: "gearshape")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.80))

            Spacer(minLength: 0)

            Button {
                onSave(draftText)
            } label: {
                Text("Save")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(Color(nsColor: .systemBlue))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!supportsTextEditing)
            .opacity(supportsTextEditing ? 1 : 0.6)
        }
        .padding(.top, 2)
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)

            if supportsTextEditing {
                TextEditor(text: $draftText)
                    .font(editorFont)
                    .foregroundStyle(Color.black)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(14)
            } else {
                Text("Editing isn’t supported for this item type")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.70))
                    .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(TextStats(text: draftText).label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
        }
    }

    private var supportsTextEditing: Bool {
        switch item.itemTypeValue {
        case .text, .richText, .code, .url, .color:
            true
        default:
            false
        }
    }

    private var editorFont: Font {
        item.itemTypeValue == .code
            ? .system(size: 16, weight: .regular, design: .monospaced)
            : .system(size: 16)
    }
}

private struct TextStats: Equatable {
    let characters: Int
    let words: Int
    let lines: Int

    init(text: String) {
        characters = text.count
        words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    var label: String {
        "\(characters) characters  •  \(words) words  •  \(lines) line\(lines == 1 ? "" : "s")"
    }
}
