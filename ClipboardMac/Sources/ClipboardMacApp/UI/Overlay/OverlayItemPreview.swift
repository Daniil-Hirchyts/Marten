import AppKit
import ClipboardCore
import SwiftUI

struct OverlayItemPreview: View {
    let item: ClipItem
    let allowPinning: Bool
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let clipItemEditor: any ClipItemEditing
    let onEdit: () -> Void
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onDelete: () -> Void

    @State var image: NSImage?
    @State var fileIcon: NSImage?
    @State var urlBannerImage: NSImage?
    @State var lastLoadedURLBannerPath: String?
    @State var lastFetchedURLBannerURLString: String?
    @State var cachedProps: CachedItemProperties?
    @State var rotationAngle: Angle = .zero
    @State var styledRichTextPreview: AttributedString?

    var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .onChange(of: item.linkPreview?.imagePath) { _, _ in
            loadURLBannerIfNeeded()
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
                actionIconButton(
                    title: "Paste",
                    systemImage: "doc.on.clipboard",
                    action: onPaste
                )
                actionIconButton(
                    title: "Paste as Plain Text",
                    systemImage: "doc.plaintext",
                    action: onPastePlainText
                )
                actionIconButton(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    action: onCopy
                )
                actionIconButton(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    action: shareItem
                )
                if allowPinning {
                    actionIconButton(
                        title: item.isPinned ? "Unpin" : "Pin",
                        systemImage: item.isPinned ? "pin.slash" : "pin",
                        action: onTogglePin
                    )
                }
                quickAddToPinboardMenu
                actionIconButton(
                    title: "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )
            }

            actionTextButton(
                title: "Edit",
                action: onEdit
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

    @ViewBuilder
    func actionIconButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        if let role {
            Button(role: role, action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 10))
            .help(title)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 10))
            .help(title)
            .accessibilityLabel(title)
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
        .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 10))
        .accessibilityLabel(title)
    }
}
