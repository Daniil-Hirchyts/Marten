import AppKit
import MartenCore
import SwiftUI

struct OverlayItemPreview: View {
    let item: ClipItem
    let allowPinning: Bool
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let clipItemEditor: any ClipItemEditing
    let onEdit: (ClipItem) -> Void
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void

    @State var image: NSImage?
    @State var fileIcon: NSImage?
    @State var cachedProps: CachedItemProperties?
    @State var rotationAngle: Angle = .zero
    @State var styledRichTextPreview: AttributedString?
    @Environment(\.colorScheme) var colorScheme

    var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar
                .zIndex(1)
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(0)
        }
        .padding(16)
        .onAppear {
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.objectID) { _, _ in
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.primaryText) { _, _ in
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.modifiedAt) { _, _ in
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(typeTitle)
                    .font(.system(size: 13, weight: .semibold))
                if let title = headerSubtitle {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                // Marten actions group
                HStack(spacing: 0) {
                    PreviewIconButton(
                        title: "Paste",
                        systemImage: "doc.on.clipboard",
                        action: { onPaste(item) },
                        applyBackground: false
                    )
                    PreviewIconButton(
                        title: "Paste as Plain Text",
                        systemImage: "doc.plaintext",
                        action: { onPastePlainText(item) },
                        applyBackground: false
                    )
                    PreviewIconButton(
                        title: "Copy",
                        systemImage: "doc.on.doc",
                        action: { onCopy(item) },
                        applyBackground: false
                    )
                    PreviewIconButton(
                        title: "Share",
                        systemImage: "square.and.arrow.up",
                        action: shareItem,
                        applyBackground: false
                    )
                    if item.itemTypeValue == .url {
                        PreviewIconButton(
                            title: "Open in Browser",
                            systemImage: "safari",
                            action: openURLInExternalBrowser,
                            applyBackground: false
                        )
                        .disabled(normalizedPrimaryURL == nil)
                    }
                }
                .padding(2)
                .adaptiveGlassBackground(shape: .capsule)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

                // Organization group
                HStack(spacing: 0) {
                    if allowPinning {
                        PreviewIconButton(
                            title: item.isPinned ? "Unpin" : "Pin",
                            systemImage: item.isPinned ? "pin.slash" : "pin",
                            action: { onTogglePin(item) },
                            applyBackground: false
                        )
                    }
                    quickAddToPinboardMenu
                }
                .padding(2)
                .adaptiveGlassBackground(shape: .capsule)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

                // Delete action
                PreviewIconButton(
                    title: "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    action: { onDelete(item) }
                )
            }

            actionTextButton(
                title: "Edit",
                action: { onEdit(item) }
            )
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.itemTypeValue {
        case .image:
            imageContent
        case .url:
            urlContent
        case .file:
            fileContent
        case .color:
            colorContent
        case .mixed:
            mixedContent
        case .code:
            scrollableText(
                item.plainTextContent ?? item.primaryText ?? "",
                monospaced: true
            )
        case .richText:
            if let styledRichTextPreview {
                scrollableStyledText(styledRichTextPreview)
            } else {
                scrollableText(
                    item.plainTextContent ?? item.primaryText ?? "",
                    monospaced: false
                )
            }
        case .text:
            scrollableText(
                item.plainTextContent ?? item.primaryText ?? "",
                monospaced: false
            )
        }
    }

    func actionTextButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(2)
        .adaptiveGlassBackground(shape: .capsule)
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        .accessibilityLabel(title)
    }
}

struct PreviewIconButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void
    var applyBackground: Bool = true
    
    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
        )
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .adaptiveGlassBackground(shape: .capsule, apply: applyBackground)
    }
}

extension View {
    @ViewBuilder
    func adaptiveGlassBackground(shape: GlassShape, apply: Bool) -> some View {
        if apply {
            self.padding(2)
                .adaptiveGlassBackground(shape: shape)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        } else {
            self
        }
    }
}
