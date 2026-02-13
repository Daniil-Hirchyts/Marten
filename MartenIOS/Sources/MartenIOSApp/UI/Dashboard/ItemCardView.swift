import MartenCore
import SwiftUI

struct ItemCardView: View {
    let item: ClipItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onPreview: () -> Void
    let onShare: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    #if canImport(UIKit)
    @State private var thumbnailImage: UIImage?
    @State private var linkPreviewImage: UIImage?
    #elseif canImport(AppKit)
    @State private var thumbnailImage: NSImage?
    @State private var linkPreviewImage: NSImage?
    #endif
    @State private var presentation: ItemCardPresentation?
    @State private var cachedImageTaskID: String?
    @State private var isPressed = false

    @Environment(\.colorScheme) private var colorScheme

    private let cardCornerRadius: CGFloat = 20
    private let cardPadding: CGFloat = 12
    private let headerMinHeight: CGFloat = 50

    private var resolvedPresentation: ItemCardPresentation {
        presentation ?? ItemCardPresentation(item: item)
    }

    var body: some View {
        let pres = resolvedPresentation

        cardContent(pres)
            .contentShape(.rect(cornerRadius: cardCornerRadius))
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(MartenAnimation.quick, value: isPressed)
            .sensoryFeedback(.selection, trigger: isSelected)
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
                isPressed = pressing
            })
            .contextMenu {
                Button { onCopy() } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { onCopyPlainText() } label: {
                    Label("Copy as Plain Text", systemImage: "textformat")
                }
                Divider()
                Button { onPreview() } label: {
                    Label("Preview", systemImage: "eye")
                }
                Button { onShare() } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button { onMove() } label: {
                    Label("Move to Pinboard", systemImage: "circle.dashed")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .onAppear {
                refreshPresentation()
                refreshImageTaskID()
            }
            .onChange(of: item.modifiedAt) {
                refreshPresentation()
                refreshImageTaskID()
            }
            .task(id: cachedImageTaskID) {
                await loadPreviewImages()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: pres))
            .accessibilityHint("Double tap to open")
            .accessibilityAddTraits(.isButton)
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
        switch resolvedPresentation.previewKind {
        case .text, .richText:
            Text(resolvedPresentation.snippet ?? "")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor(for: resolvedPresentation))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(resolvedPresentation.snippet ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(secondaryTextColor(for: resolvedPresentation))
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
            Text(resolvedPresentation.snippet ?? "Mixed item")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor(for: resolvedPresentation))
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
        ZStack {
            if let linkPreviewImage {
                #if canImport(UIKit)
                Image(uiImage: linkPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                #elseif canImport(AppKit)
                Image(nsImage: linkPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                #endif
            } else {
                Rectangle()
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.05)
                    )

                Image(systemName: "link")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color.white.opacity(0.35)
                            : Color.black.opacity(0.25)
                    )
            }
        }
    }

    private var filePreview: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            Image(systemName: "doc.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(secondaryTextColor(for: resolvedPresentation))

            if let fileName = resolvedPresentation.fileName {
                Text(fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(primaryTextColor(for: resolvedPresentation))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var colorPreview: some View {
        let hex = resolvedPresentation.colorHex ?? "#808080"
        let background = Color(hex: hex, fallback: .gray)
        let foreground = ColorHex.foregroundColor(
            for: ColorHex.normalizedHex(from: hex) ?? "#808080"
        )

        return RoundedRectangle(cornerRadius: 10)
            .fill(background)
            .frame(height: 56)
            .overlay {
                Text(resolvedPresentation.snippet ?? hex)
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

    private func refreshPresentation() {
        presentation = ItemCardPresentation(item: item)
    }

    private func refreshImageTaskID() {
        cachedImageTaskID = "\(item.objectID.uriRepresentation().absoluteString)-\(item.modifiedAt.timeIntervalSince1970)"
    }

    private func loadPreviewImages() async {
        let pres = resolvedPresentation
        if pres.previewKind == .image {
            thumbnailImage = await ImageThumbnailLoader.shared.loadThumbnail(for: item)
        } else {
            thumbnailImage = nil
        }

        if pres.previewKind == .link,
            let path = item.linkPreview?.imagePath,
            !path.isEmpty
        {
            linkPreviewImage = await loadImageFromDisk(path: path)
        } else {
            linkPreviewImage = nil
        }
    }

    #if canImport(UIKit)
    private func loadImageFromDisk(path: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: UIImage(contentsOfFile: path))
            }
        }
    }
    #elseif canImport(AppKit)
    private func loadImageFromDisk(path: String) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: NSImage(contentsOfFile: path))
            }
        }
    }
    #endif
}
