import MartenCore
import SwiftUI

struct ItemCardView: View {
    @ObservedObject private var item: ClipItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let handlesTapGesture: Bool
    let handlesPressGesture: Bool
    let showsContextMenu: Bool
    let showsSelectionFeedback: Bool
    let allowPinning: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onTogglePin: () -> Void
    let onShare: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    init(
        item: ClipItem,
        isSelectionMode: Bool,
        isSelected: Bool,
        handlesTapGesture: Bool = true,
        handlesPressGesture: Bool = true,
        showsContextMenu: Bool = true,
        showsSelectionFeedback: Bool = true,
        allowPinning: Bool = false,
        onTap: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onCopyPlainText: @escaping () -> Void,
        onPreview: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onTogglePin: @escaping () -> Void = {},
        onShare: @escaping () -> Void,
        onMove: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        _item = ObservedObject(wrappedValue: item)
        let initialPresentation = ItemCardPresentation(item: item)
        _presentation = State(initialValue: initialPresentation)
        _cachedImageTaskID = State(initialValue: Self.makeImageTaskID(for: item))
        _cachedLinkPreviewTaskID = State(initialValue: Self.makeLinkPreviewTaskID(for: item))
        _cachedIsPinned = State(initialValue: item.isPinned)
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.handlesTapGesture = handlesTapGesture
        self.handlesPressGesture = handlesPressGesture
        self.showsContextMenu = showsContextMenu
        self.showsSelectionFeedback = showsSelectionFeedback
        self.allowPinning = allowPinning
        self.onTap = onTap
        self.onCopy = onCopy
        self.onCopyPlainText = onCopyPlainText
        self.onPreview = onPreview
        self.onEdit = onEdit
        self.onTogglePin = onTogglePin
        self.onShare = onShare
        self.onMove = onMove
        self.onDelete = onDelete
    }

    #if canImport(UIKit)
    @State private var thumbnailImage: UIImage?
    @State private var linkPreviewResult: LinkPreviewImageResult?
    #elseif canImport(AppKit)
    @State private var thumbnailImage: NSImage?
    @State private var linkPreviewResult: LinkPreviewImageResult?
    #endif
    @State private var presentation: ItemCardPresentation
    @State private var cachedImageTaskID: String?
    @State private var cachedLinkPreviewTaskID: String
    @State private var cachedIsPinned: Bool
    @State private var isPressed = false

    @Environment(\.colorScheme) private var colorScheme

    private let cardCornerRadius: CGFloat = 20
    private let cardPadding: CGFloat = 10
    private let headerMinHeight: CGFloat = 42

    var body: some View {
        let pres = presentation

        tapWrappedContent(cardContent(pres))
            .contentShape(.rect(cornerRadius: cardCornerRadius))
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(MartenAnimation.quick, value: isPressed)
            .modifier(PressGestureModifier(isEnabled: handlesPressGesture, isPressed: $isPressed))
            .modifier(SelectionFeedbackModifier(isEnabled: showsSelectionFeedback, isSelected: isSelected))
            .modifier(ContextMenuModifier(
                isEnabled: showsContextMenu,
                allowPinning: allowPinning,
                isPinned: cachedIsPinned,
                onCopy: onCopy,
                onCopyPlainText: onCopyPlainText,
                onPreview: onPreview,
                onEdit: onEdit,
                onTogglePin: onTogglePin,
                onShare: onShare,
                onMove: onMove,
                onDelete: onDelete
            ))
            .onAppear {
                refreshSnapshotState()
            }
            .onReceive(item.objectWillChange) {
                refreshSnapshotState()
            }
            .task(id: cachedImageTaskID) {
                await loadThumbnailImage()
            }
            .task(id: cachedLinkPreviewTaskID) {
                // Separate task for link preview images - triggers when linkPreview.id changes
                await loadLinkPreviewImage()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: pres))
            .accessibilityHint("Double tap to open")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func tapWrappedContent<Content: View>(_ content: Content) -> some View {
        if handlesTapGesture {
            content.onTapGesture { onTap() }
        } else {
            content
        }
    }

    private func cardContent(_ pres: ItemCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ItemCardHeaderView(
                presentation: pres,
                isSelectionMode: isSelectionMode,
                isSelected: isSelected,
                allowPinning: allowPinning,
                isPinned: cachedIsPinned,
                cardCornerRadius: cardCornerRadius,
                cardPadding: cardPadding,
                headerMinHeight: headerMinHeight
            )

            VStack(alignment: .leading, spacing: 0) {
                if isEdgeToEdgeContent(pres) {
                    ItemCardPreviewContent(
                        presentation: pres,
                        thumbnailImage: thumbnailImage,
                        linkPreviewResult: linkPreviewResult
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ItemCardPreviewContent(
                            presentation: pres,
                            thumbnailImage: thumbnailImage,
                            linkPreviewResult: linkPreviewResult
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, cardPadding)
                    .padding(.top, 8)
                }

                cardFooter(pres)
                    .padding(.horizontal, cardPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackgroundColor(for: pres))
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : cardBorderColor(for: pres),
                    lineWidth: isSelected ? 4 : 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12),
            radius: isSelected ? 6 : 4,
            x: 0,
            y: isSelected ? 3 : 2
        )
        .aspectRatio(1, contentMode: .fit)
    }

    private func cardFooter(_ pres: ItemCardPresentation) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(pres.footerLeadingText)
                .font(.system(size: 10))
                .foregroundStyle(tertiaryTextColor(for: pres))

            Spacer(minLength: 0)

            Text(pres.footerTrailingText)
                .font(.system(size: 10))
                .foregroundStyle(tertiaryTextColor(for: pres))
                .lineLimit(1)
        }
    }

    private func isEdgeToEdgeContent(_ pres: ItemCardPresentation) -> Bool {
        pres.previewKind == .image || pres.previewKind == .link || pres.previewKind == .color
    }

    private func cardBackgroundColor(for pres: ItemCardPresentation) -> Color {
        return colorScheme == .dark
            ? Color(.sRGB, white: 0.04, opacity: 0.72)
            : Color(.sRGB, white: 0.96, opacity: 0.9)
    }

    private func cardBorderColor(for pres: ItemCardPresentation) -> Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalized, fallback: .gray).opacity(0.35)
        }

        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalized).opacity(0.3)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.12)
    }

    private func tertiaryTextColor(for pres: ItemCardPresentation) -> Color {
        return colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private func accessibilityLabel(for pres: ItemCardPresentation) -> String {
        var parts: [String] = [pres.title]

        if let subtitle = pres.headerSubtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }

        parts.append(pres.footerLeadingText)
        parts.append(pres.footerTrailingText)

        if isSelected {
            parts.append("selected")
        }

        return parts.joined(separator: ", ")
    }

    private var isItemSnapshotAvailable: Bool {
        item.managedObjectContext != nil && !item.isDeleted
    }

    private static func makeImageTaskID(for item: ClipItem) -> String {
        let linkPreviewID = item.linkPreview?.id.uuidString ?? "none"
        let linkPreviewTimestamp = item.linkPreview?.fetchedAt.timeIntervalSince1970 ?? 0
        return
            "\(item.objectID.uriRepresentation().absoluteString)-\(item.modifiedAt.timeIntervalSince1970)-\(linkPreviewID)-\(linkPreviewTimestamp)"
    }

    private static func makeLinkPreviewTaskID(for item: ClipItem) -> String {
        item.linkPreview?.id.uuidString
            ?? "no-link-preview-\(item.objectID.uriRepresentation().absoluteString)"
    }

    private func refreshSnapshotState() {
        guard isItemSnapshotAvailable else { return }
        presentation = ItemCardPresentation(item: item)
        cachedIsPinned = item.isPinned
        cachedImageTaskID = Self.makeImageTaskID(for: item)
        cachedLinkPreviewTaskID = Self.makeLinkPreviewTaskID(for: item)
    }

    private func loadThumbnailImage() async {
        guard isItemSnapshotAvailable else {
            thumbnailImage = nil
            return
        }
        let pres = presentation
        if pres.previewKind == .image {
            thumbnailImage = await ImageThumbnailLoader.shared.loadThumbnail(for: item)
        } else {
            thumbnailImage = nil
        }
    }

    private func loadLinkPreviewImage() async {
        guard isItemSnapshotAvailable else {
            linkPreviewResult = nil
            return
        }
        let pres = presentation
        if pres.previewKind == .link, let linkPreview = item.linkPreview {
            linkPreviewResult = await LinkPreviewImageLoader.shared.loadImage(for: linkPreview)
        } else {
            linkPreviewResult = nil
        }
    }
}
