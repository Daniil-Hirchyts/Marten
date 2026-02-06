import ClipboardCore
import SwiftUI

extension PinboardTabBar {
    @ViewBuilder
    func editorView(pinboard: Pinboard?) -> some View {
        let isStyleOnlyEditor = pinboard != nil && isStyleOnlyEditMode
        let fixedEditorWidth = existingPinboardEditorWidth(pinboard)
        let nameFieldMinWidth: CGFloat = pinboard == nil ? 40 : 0
        let editorMinWidth = minTabWidth

        HStack(spacing: 6) {
            PinboardStylePickerButton(
                selectedColorHex: draftColor,
                selectedSign: draftIcon,
                shouldPresentOnAppear: $shouldPresentStylePickerFromMenu,
                onWillOpen: {
                    commitState = .suppress
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                },
                onColorSelect: { newColor in
                    draftColor = newColor
                    if let pinboard {
                        onColorChange(pinboard, newColor)
                    }
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                    commitState = .suppress
                },
                onSignSelect: { newSign in
                    draftIcon = newSign
                    if let pinboard {
                        onIconChange(pinboard, newSign)
                    }
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                    commitState = .suppress
                }
            )

            if isStyleOnlyEditor {
                Text(pinboard?.name ?? draftName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(editorTextColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: nameFieldMinWidth, alignment: .leading)
            } else {
                ZStack(alignment: .leading) {
                    Text(draftName.isEmpty ? "Name" : draftName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.clear)
                        .padding(.vertical, 0)
                        .layoutPriority(1)

                    if draftName.isEmpty {
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(editorPlaceholderColor)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $draftName) { editing in
                        if !editing {
                            handleBlurCommit()
                        }
                    } onCommit: {
                        handleCommitButton()
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(editorTextColor)
                    .tint(editorTextColor)
                    .focused($isFocused)
                    .accessibilityIdentifier("overlay.pinboard.editor.name")
                    .accessibilityLabel("Pinboard name")
                    .accessibilityValue(draftName.isEmpty ? "Empty" : draftName)
                    .accessibilityHint("Enter a pinboard name")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isFocused = true
                        }
                    }
                }
                .frame(minWidth: nameFieldMinWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: tabContentHeight, alignment: .center)
        .padding(.vertical, tabVerticalPadding)
        .padding(.horizontal, tabHorizontalPadding)
        .background(
            Group {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassNavigationStyle()
                } else {
                    (colorScheme == .dark ? Color.white : Color.black).opacity(DesignTokens.Opacity.backgroundStrong)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Group {
                if #available(macOS 26.0, *) {
                    EmptyView()
                } else {
                    Capsule()
                        .stroke(
                            (colorScheme == .dark ? Color.white : Color.black).opacity(isFocused ? DesignTokens.Opacity.borderStrong : 0),
                            lineWidth: 1)
                }
            }
        )
        .fixedSize(horizontal: fixedEditorWidth == nil, vertical: false)
        .frame(
            minWidth: fixedEditorWidth == nil ? editorMinWidth : fixedEditorWidth,
            maxWidth: fixedEditorWidth == nil ? maxTabWidth : fixedEditorWidth,
            alignment: .leading
        )
        .frame(height: headerButtonSize)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PinboardLayoutInfoKey.self,
                    value: PinboardLayoutInfo(editorOverlayFrame: overlayFrame(from: proxy))
                )
            }
        )
    }

    func existingPinboardEditorWidth(_ pinboard: Pinboard?) -> CGFloat? {
        guard let pinboard, isStyleOnlyEditMode else { return nil }
        if pinnedEditorObjectID == pinboard.objectID, let pinnedEditorWidth, pinnedEditorWidth > 0 {
            return min(pinnedEditorWidth, maxTabWidth)
        }
        guard let width = frameManager.latestTabFrames[pinboard.objectID]?.width, width > 0 else {
            return nil
        }
        return min(width, maxTabWidth)
    }

    func handleBlurCommit() {
        guard editingID != nil else { return }

        DispatchQueue.main.async {
            if isStyleOnlyEditMode {
                isStyleOnlyEditMode = false
                onCancel()
                return
            }

            switch commitState {
            case .cancel:
                commitState = .none
                return
            case .commit:
                commitState = .none
                return
            case .suppress:
                commitState = .none
                return
            case .none:
                break
            }

            if let window = NSApp.windows.first(where: { $0.isKeyWindow }), window.isVisible {
                onCommit()
            } else {
                onCancel()
            }
        }
    }

    func handleCommitButton() {
        if isStyleOnlyEditMode {
            isStyleOnlyEditMode = false
            onCancel()
            return
        }
        commitState = .commit
        onCommit()
        isFocused = false
    }

    var editorTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var editorPlaceholderColor: Color {
        colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.3)
    }
}
