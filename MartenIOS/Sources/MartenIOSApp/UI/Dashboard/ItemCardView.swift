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
    private let cardPadding: CGFloat = 12
    private let headerMinHeight: CGFloat = 50

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
            cardHeader(pres)

            VStack(alignment: .leading, spacing: 0) {
                if isEdgeToEdgeContent(pres) {
                    previewContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        previewContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, cardPadding)
                    .padding(.top, 10)
                }

                cardFooter(pres)
                    .padding(.horizontal, cardPadding)
                    .padding(.top, 8)
                    .padding(.bottom, cardPadding)
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

    private func cardHeader(_ pres: ItemCardPresentation) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pres.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(headerTextColor(for: pres))
                    .lineLimit(1)

                if let subtitle = pres.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(headerTextColor(for: pres).opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let colorHex = pres.primaryPinboardColorHex,
               let sign = pres.primaryPinboardSign {
                PinboardIndicator(
                    colorHex: colorHex,
                    sign: sign,
                    size: 30,
                    showBorder: false
                )
            } else {
                SourceAppIconBadge(
                    bundleID: pres.sourceAppBundleID,
                    appName: pres.sourceAppDisplayName,
                    iconData: pres.sourceAppIconData,
                    size: 30
                )
            }

            if allowPinning, item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(headerTextColor(for: pres).opacity(0.85))
            }

            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor
                            : headerTextColor(for: pres).opacity(0.72)
                    )
                    .animation(MartenAnimation.quick, value: isSelected)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: headerMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: cardCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cardCornerRadius
            )
            .fill(headerBackgroundColor(for: pres))
        )
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

    @ViewBuilder
    private var previewContent: some View {
        switch presentation.previewKind {
        case .text, .richText:
            Text(presentation.snippet ?? "")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor(for: presentation))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(presentation.snippet ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(secondaryTextColor(for: presentation))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .link:
            linkPreview
        case .image:
            imagePreview
        case .file:
            filePreview
        case .color:
            colorPreview
        case .mixed:
            Text(presentation.snippet ?? "Mixed item")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor(for: presentation))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var imagePreview: some View {
        ZStack {
            TransparencyGrid(squareSize: 10)

            if let thumbnailImage {
                #if canImport(UIKit)
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                #elseif canImport(AppKit)
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                #endif
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
            }
        }
    }

    private var linkPreview: some View {
        GeometryReader { geometry in
            ZStack {
                switch linkPreviewResult {
                case .banner(let image):
                    #if canImport(UIKit)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    #endif
                case .favicon(let image):
                    linkPreviewPlaceholderBackground
                    #if canImport(UIKit)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    #endif
                case nil:
                    linkPreviewPlaceholderBackground
                    Image(systemName: "link")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            colorScheme == .dark
                                ? Color.white.opacity(0.35)
                                : Color.black.opacity(0.25)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }

    private var linkPreviewPlaceholderBackground: some View {
        Rectangle()
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.05)
            )
    }

    private var filePreview: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            Image(systemName: "doc.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(secondaryTextColor(for: presentation))

            if let fileName = presentation.fileName {
                Text(fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(primaryTextColor(for: presentation))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var colorPreview: some View {
        let hex = presentation.colorHex ?? "#808080"
        let background = Color(hex: hex, fallback: .gray)
        let foreground = ColorHex.foregroundColor(
            for: ColorHex.normalizedHex(from: hex) ?? "#808080"
        )

        return RoundedRectangle(cornerRadius: 10)
            .fill(background)
            .frame(height: 56)
            .overlay {
                Text(presentation.snippet ?? hex)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
    }

    private func isEdgeToEdgeContent(_ pres: ItemCardPresentation) -> Bool {
        pres.previewKind == .image || pres.previewKind == .link
    }

    private func sourceIconDescriptor(for pres: ItemCardPresentation) -> SourceAppIconDescriptor {
        SourceAppIconDescriptor.resolve(bundleID: pres.sourceAppBundleID, appName: pres.sourceAppDisplayName)
    }

    private func headerBackgroundColor(for pres: ItemCardPresentation) -> Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalized, fallback: .gray).opacity(0.96)
        }

        return sourceIconDescriptor(for: pres).backgroundColor.opacity(0.94)
    }

    private func headerTextColor(for pres: ItemCardPresentation) -> Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            return ColorHex.foregroundColor(for: normalized)
        }

        return sourceIconDescriptor(for: pres).foregroundColor
    }

    private func cardBackgroundColor(for pres: ItemCardPresentation) -> Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return Color(hex: normalized, fallback: .gray)
        }

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

    private func primaryTextColor(for pres: ItemCardPresentation) -> Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalized)
        }

        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    private func secondaryTextColor(for pres: ItemCardPresentation) -> Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalized).opacity(0.8)
        }

        return colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
    }

    private func tertiaryTextColor(for pres: ItemCardPresentation) -> Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalized).opacity(0.7)
        }

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

private struct PressGestureModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
                isPressed = pressing
            })
        } else {
            content
        }
    }
}

private struct SelectionFeedbackModifier: ViewModifier {
    let isEnabled: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.sensoryFeedback(.selection, trigger: isSelected)
        } else {
            content
        }
    }
}

private struct ContextMenuModifier: ViewModifier {
    let isEnabled: Bool
    let allowPinning: Bool
    let isPinned: Bool
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onPreview: () -> Void
    let onTogglePin: () -> Void
    let onShare: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                ForEach(ItemCardContextAction.ordered(allowPinning: allowPinning), id: \.self) { action in
                    button(for: action)
                    if showsDivider(after: action) {
                        Divider()
                    }
                }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func button(for action: ItemCardContextAction) -> some View {
        if action == .togglePin {
            Button { perform(action) } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
        } else if action.isDestructive {
            Button(role: .destructive) { perform(action) } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        } else {
            Button { perform(action) } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }

    private func perform(_ action: ItemCardContextAction) {
        switch action {
        case .copy:
            onCopy()
        case .copyPlainText:
            onCopyPlainText()
        case .preview:
            onPreview()
        case .togglePin:
            onTogglePin()
        case .share:
            onShare()
        case .moveToPinboard:
            onMove()
        case .delete:
            onDelete()
        }
    }

    private func showsDivider(after action: ItemCardContextAction) -> Bool {
        action == .copyPlainText || action == .togglePin || action == .moveToPinboard
    }
}
