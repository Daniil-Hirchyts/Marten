import AppKit
import MartenCore
import Foundation
import SwiftUI

struct CachedItemProperties {
    let typeLabel: String
    let typeIcon: String
    let displayTitle: String
    let primaryTitle: String
    let previewText: String?
    let detailLines: [String]?
    let statsLabel: String
    let shouldShowPrimaryTitle: Bool
    let primaryPinboardColor: Color?
    let primaryPinboardColorHex: String?
    let primaryPinboardName: String?
    let primaryPinboardSign: String?
    let sourceLabel: String?

    init(item: ClipItem) {
        let itemType = item.itemTypeValue

        self.typeLabel = Self.computeTypeLabel(for: itemType)
        self.typeIcon = Self.computeTypeIcon(for: itemType)
        self.shouldShowPrimaryTitle = itemType == .file || itemType == .url

        if let customTitle = item.customTitle, !customTitle.isEmpty {
            self.displayTitle = customTitle
        } else {
            self.displayTitle = self.typeLabel
        }

        self.primaryTitle = Self.computePrimaryTitle(for: item, itemType: itemType)
        self.previewText = Self.computePreviewText(for: item, itemType: itemType)
        self.detailLines = Self.computeDetailLines(for: item, itemType: itemType)
        self.statsLabel = Self.computeStatsLabel(for: item, itemType: itemType)

        let pinboardInfo = Self.computePrimaryPinboard(for: item)
        self.primaryPinboardColor = pinboardInfo.color
        self.primaryPinboardColorHex = pinboardInfo.colorHex
        self.primaryPinboardName = pinboardInfo.name
        self.primaryPinboardSign = pinboardInfo.sign

        self.sourceLabel = Self.computeSourceLabel(for: item)
    }

    private static func computeTypeLabel(for itemType: ItemType) -> String {
        switch itemType {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "URL"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }

    private static func computeTypeIcon(for itemType: ItemType) -> String {
        switch itemType {
        case .text: return "textformat"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .code: return "chevron.left.slash.chevron.right"
        case .color: return "paintpalette"
        case .mixed: return "square.stack"
        }
    }

    private static func computePrimaryTitle(for item: ClipItem, itemType: ItemType) -> String {
        let text = item.primaryText ?? "Untitled"
        switch itemType {
        case .file:
            let fileURL = URL(fileURLWithPath: text)
            if fileURL.isFileURL {
                return fileURL.lastPathComponent
            }
            return text.isEmpty ? "File" : text
        case .url:
            if let previewTitle = item.linkPreview?.title, !previewTitle.isEmpty {
                return previewTitle
            }
            if let siteName = item.linkPreview?.siteName, !siteName.isEmpty {
                return siteName
            }
            if let url = URL(string: text), let host = url.host {
                return host
            }
            return text.isEmpty ? "URL" : text
        case .image:
            return "Image"
        case .richText:
            return text.isEmpty ? "Rich Text" : text
        case .text:
            return text.isEmpty ? "Text" : text
        case .code:
            return text.isEmpty ? "Code" : text
        case .color:
            return text.isEmpty ? "Color" : text
        case .mixed:
            return text.isEmpty ? "Mixed" : text
        }
    }

    private static func computePreviewText(for item: ClipItem, itemType: ItemType) -> String? {
        guard let text = item.primaryText, !text.isEmpty else { return nil }
        switch itemType {
        case .text, .richText, .code:
            return text
        case .color:
            return nil
        default:
            return nil
        }
    }

    private static func computeDetailLines(for item: ClipItem, itemType: ItemType) -> [String]? {
        switch itemType {
        case .url:
            if let text = item.primaryText, let url = URL(string: text) {
                let host = url.host ?? "URL"
                let path = url.path.isEmpty ? "/" : url.path
                if let siteName = item.linkPreview?.siteName, !siteName.isEmpty {
                    return [siteName, path]
                }
                return [host, path]
            }
            return nil
        case .file:
            return nil
        default:
            return nil
        }
    }

    private static func computeStatsLabel(for item: ClipItem, itemType: ItemType) -> String {
        switch itemType {
        case .text, .richText, .code:
            let count = item.primaryText?.count ?? 0
            return "\(count) chars"
        case .color:
            return "Color"
        default:
            return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        }
    }

    private static func computePrimaryPinboard(for item: ClipItem) -> (color: Color?, colorHex: String?, name: String?, sign: String?) {
        let pinboards = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        let sorted = pinboards.sorted { $0.sortOrder < $1.sortOrder }
        guard let pinboard = sorted.first else { return (nil, nil, nil, nil) }
        return (Color(hex: pinboard.colorHex, fallback: .gray), pinboard.colorHex, pinboard.name, pinboard.iconName)
    }

    private static func computeSourceLabel(for item: ClipItem) -> String? {
        if let appName = item.sourceAppName, !appName.isEmpty {
            return appName
        }
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
            let components = bundleID.split(separator: ".")
            if let lastComponent = components.last {
                return String(lastComponent)
            }
            return bundleID
        }
        return nil
    }
}

enum PreviewFactory {
    @ViewBuilder
    static func makePreview(
        for itemType: ItemType,
        typeIcon: String,
        thumbnailImage: NSImage?,
        urlHost: String,
        urlPath: String,
        fileIcon: NSImage?,
        fileName: String,
        fileSizeText: String?,
        previewText: String?,
        colorScheme: ColorScheme
    ) -> some View {
        Group {
            switch itemType {
            case .image:
                ImagePreview(image: thumbnailImage)
            case .url:
                if let thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    URLPreview(host: urlHost, path: urlPath)
                }
            case .file:
                FilePreview(icon: fileIcon, name: fileName, size: fileSizeText)
            case .code:
                CodePreview(text: previewText ?? "")
            case .richText, .text:
                TextPreview(text: previewText ?? "")
            case .color:
                ColorPreview(hex: previewText ?? "")
            case .mixed:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(DesignTokens.Opacity.backgroundSubtle)
                                : Color.black.opacity(0.05)
                        )
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .frame(width: 72, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(DesignTokens.Opacity.backgroundSubtle)
                        : Color.black.opacity(0.05)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension ItemCard {
    var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .focused($isFocused)
                    .onSubmit {
                        onCommitRename(item, editTitle)
                    }
                    .accessibilityIdentifier("overlay.itemCard.\(item.id.uuidString).title")
                    .accessibilityLabel("Item title")
                    .accessibilityValue(editTitle.isEmpty ? "Empty" : editTitle)
                    .accessibilityHint("Enter a new title")
                    .onAppear {
                        editTitle = item.customTitle ?? cached.typeLabel
                        isFocused = true
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cached.displayTitle)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                        .lineLimit(1)

                    if let subtitle = headerSubtitle {
                        Text(subtitle)
                            .font(.system(size: subtitleFontSize, weight: .medium))
                            .foregroundStyle(headerTextColor.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let primaryColorHex = cached.primaryPinboardColorHex,
               let primarySign = cached.primaryPinboardSign
            {
                PinboardIndicator(
                    colorHex: primaryColorHex,
                    sign: primarySign,
                    size: 30
                )
            } else if cached.primaryPinboardColor == nil,
                let bundleID = item.sourceAppBundleID,
                !bundleID.isEmpty
            {
                AppIconView(bundleID: bundleID, size: 30)
            }

            if showPinIndicator, item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, isCompactSize ? 8 : 10)
        .frame(minHeight: headerMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
    }

    var contentPreviewView: some View {
        Group {
            if item.itemTypeValue == .color, let text = item.primaryText {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: colorFontSize, weight: .semibold))
                        .foregroundStyle(colorItemForeground ?? primaryTextColor)
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else if item.itemTypeValue == .image {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        if let image = thumbnailImage {
                            ZStack {
                                TransparencyGrid(squareSize: 12)
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                            }
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            ZStack {
                                Image(systemName: "photo")
                                    .font(.system(size: isCompactSize ? 36 : 48, weight: .light))
                                    .foregroundStyle(
                                        colorScheme == .dark
                                            ? Color.white.opacity(0.3)
                                            : Color.black.opacity(0.2)
                                    )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                        }

                        if let fileName = imageFileNameShortened {
                            Text(fileName)
                                .font(.system(size: isCompactSize ? 9 : 11, weight: .medium))
                                .foregroundStyle(primaryTextColor)
                                .lineLimit(1)
                                .padding(.horizontal, isCompactSize ? 8 : 12)
                                .padding(.vertical, isCompactSize ? 4 : 6)
                                .frame(maxWidth: .infinity)
                                .layoutPriority(0)
                        }
                    }

                    if let resolution = imageResolution {
                        Text(resolution)
                            .font(.system(size: isCompactSize ? 8 : 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, isCompactSize ? 4 : 6)
                            .padding(.vertical, isCompactSize ? 2 : 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(isCompactSize ? 6 : 8)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if item.itemTypeValue == .url {
                VStack(alignment: .leading, spacing: isCompactSize ? 5 : 6) {
                    URLBannerPreview(
                        image: urlBannerImage,
                        host: urlHost,
                        path: urlPath,
                        isCompact: isCompactSize
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: urlBannerHeight)
                    .clipped()

                    Text(urlDisplayText)
                        .font(.system(size: isCompactSize ? 9 : 10, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .task(id: urlBannerTaskID) {
                    await fetchURLBannerIfNeeded()
                }
            } else if item.itemTypeValue == .file {
                VStack(spacing: isCompactSize ? 2 : 4) {
                    Spacer(minLength: 0)
                    if let icon = fileIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: fileIconSize, height: fileIconSize)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: fileIconSize * 0.7, weight: .regular))
                            .foregroundStyle(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.4)
                                    : Color.black.opacity(0.3)
                            )
                    }

                    if let fileName = fileNameOnly {
                        Text(fileName)
                            .font(.system(size: isCompactSize ? 9 : 10, weight: .medium))
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                            .padding(.top, isCompactSize ? 2 : 3)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                Group {
                    if shouldShowLeadingPreview {
                        HStack(alignment: .top, spacing: 10) {
                            PreviewFactory.makePreview(
                                for: item.itemTypeValue,
                                typeIcon: cached.typeIcon,
                                thumbnailImage: thumbnailImage,
                                urlHost: urlHost,
                                urlPath: urlPath,
                                fileIcon: fileIconImage,
                                fileName: cached.primaryTitle,
                                fileSizeText: fileSizeText,
                                previewText: cached.previewText,
                                colorScheme: colorScheme
                            )

                            textDetailStack
                        }
                    } else {
                        textDetailStack
                    }
                }
            }
        }
    }

    var urlBannerHeight: CGFloat {
        let preferredHeight: CGFloat = isCompactSize ? 82 : 112
        let contentTopPadding: CGFloat = isCompactSize ? 8 : 10
        let contentSpacing: CGFloat = isCompactSize ? 8 : 10
        let footerReserve: CGFloat = 18
        let urlTextReserve: CGFloat = isCompactSize ? 16 : 18
        let availableHeight =
            cardSize
            - headerMinHeight
            - cardPadding
            - contentTopPadding
            - contentSpacing
            - footerReserve
            - urlTextReserve

        return max(32, min(preferredHeight, max(0, availableHeight)))
    }

    var textDetailStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            if cached.shouldShowPrimaryTitle {
                Text(cached.primaryTitle)
                    .font(.system(size: contentFontSize, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
            }

            if let styledPreview = richTextPreview {
                Text(styledPreview)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(maxPreviewLines)
            } else if let preview = cached.previewText {
                Text(preview)
                    .font(.system(size: contentFontSize))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(maxPreviewLines)
            } else if let details = cached.detailLines {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.system(size: contentFontSize))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }
        }
    }

    var richTextPreview: AttributedString? {
        guard item.itemTypeValue == .richText else { return nil }
        return styledPreviewText
    }

    var footerView: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(tertiaryTextColor)

            Spacer()

            Text(cached.statsLabel)
                .font(.system(size: 10))
                .foregroundStyle(tertiaryTextColor)
        }
    }
}
