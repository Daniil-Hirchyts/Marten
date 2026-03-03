import AppKit
import MartenCore
import Foundation
import SwiftUI

struct ItemCompactRow: View {
    private static let compactTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private let cardCornerRadius: CGFloat = 12
    private let sideBarWidth: CGFloat = 38

    let item: ClipItem
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    var itemPinboardSignature: Int = 0
    let isSelected: Bool
    let isEditing: Bool
    let allowPinning: Bool
    let readOnly: Bool
    let clipItemEditor: any ClipItemEditing
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onConvertType: (ClipItem, ItemType) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onEdit: (ClipItem) -> Void
    let onRename: (ClipItem) -> Void
    let onCommitRename: (ClipItem, String) -> Void
    let onTap: (ClipItem) -> Void
    let onDoubleTap: (ClipItem) -> Void
    @Binding var previewItemID: NSManagedObjectID?
    @Binding var isPreviewPopoverPresented: Bool

    @State var thumbnailImage: NSImage?
    @State var linkPreviewResult: LinkPreviewImageResult?
    @State var lastLoadedThumbnailPath: String?
    @State var lastLoadedLinkPreviewKey: String?
    @State private var lastTapTime: Date?
    @State private var editTitle = ""
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isPreviewPresentedBinding: Binding<Bool> {
        Binding(
            get: { isPreviewPopoverPresented && previewItemID == item.objectID },
            set: { newValue in
                if !newValue {
                    if previewItemID == item.objectID {
                        previewItemID = nil
                    }
                    isPreviewPopoverPresented = false
                }
            }
        )
    }

    private var cardShadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1)
    }

    private var cardShadowRadius: CGFloat {
        isSelected ? 5 : 3
    }

    private var cardShadowY: CGFloat {
        isSelected ? 2 : 1
    }

    var body: some View {

        mainRowContent
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(rowBackground)
            .clipShape(cardShape)
            .shadow(
                color: cardShadowColor,
                radius: cardShadowRadius,
                x: 0,
                y: cardShadowY
            )
            .contentShape(cardShape)
            .overlay(selectionBorder)
            .onTapGesture {
                handleTap()
            }
            .onAppear {
                refreshPreviewAssets()
            }
            .onChange(of: contentSignature) { oldValue, newValue in
                handleContentSignatureChange(oldValue: oldValue, newValue: newValue)
            }
            .popover(isPresented: isPreviewPresentedBinding, arrowEdge: .trailing) {
                popoverContent
            }
            .contextMenu {
                contextMenuContent
            }
            .accessibilityElement(children: isEditing ? .contain : .ignore)
            .accessibilityIdentifier("overlay.itemCompact.\(item.id.uuidString)")
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Single click to select, double click to paste")
            .accessibilityAddTraits(.isButton)
    }

    private func handleContentSignatureChange(oldValue: ContentSignature, newValue: ContentSignature) {
        if item.isDeleted || item.managedObjectContext == nil { return }
        
        if oldValue.primaryText != newValue.primaryText {
            DispatchQueue.main.async {
                linkPreviewResult = nil
                lastLoadedLinkPreviewKey = nil
            }
        }

        if oldValue.thumbnailPath != newValue.thumbnailPath {
            refreshThumbnailImage()
        }

        if oldValue.representationAssetSignature != newValue.representationAssetSignature {
            refreshThumbnailImage()
        }

        if oldValue.linkPreviewImagePath != newValue.linkPreviewImagePath
            || oldValue.primaryText != newValue.primaryText
        {
            refreshLinkPreview()
        }

        if oldValue.modifiedAt != newValue.modifiedAt || oldValue.itemType != newValue.itemType {
            refreshPreviewAssets()
        }
    }

    private var mainRowContent: some View {
        HStack(spacing: 10) {
            leadingVisual

            if !hasBannerLayer {
                VStack(alignment: .leading, spacing: 3) {
                    titleView
                }
            }

            Spacer(minLength: 0)

            rightInfoColumn
        }
    }

    private var popoverContent: some View {
        OverlayItemPreview(
            item: item,
            allowPinning: allowPinning,
            pinboards: pinboards,
            lockedPinboardIDs: lockedPinboardIDs,
            clipItemEditor: clipItemEditor,
            onEdit: { editedItem in
                previewItemID = nil
                isPreviewPopoverPresented = false
                onEdit(editedItem)
            },
            onPaste: { pastedItem in
                onPaste(pastedItem)
                previewItemID = nil
                isPreviewPopoverPresented = false
            },
            onPastePlainText: { pastedItem in
                onPastePlainText(pastedItem)
                previewItemID = nil
                isPreviewPopoverPresented = false
            },
            onCopy: { copiedItem in
                onCopy(copiedItem)
                previewItemID = nil
                isPreviewPopoverPresented = false
            },
            onTogglePin: { toggledItem in
                onTogglePin(toggledItem)
            },
            onMoveToPinboard: { movedItem, pinboard in
                onMoveToPinboard(movedItem, pinboard)
            },
            onCreatePinboard: { sourceItem in
                previewItemID = nil
                isPreviewPopoverPresented = false
                onCreatePinboard(sourceItem)
            },
            onDelete: { deletedItem in
                onDelete(deletedItem)
                previewItemID = nil
                isPreviewPopoverPresented = false
            }
        )
        .frame(
            width: item.shouldUseLargePreviewPopover ? 920 : 560,
            height: item.shouldUseLargePreviewPopover ? 640 : 380
        )
    }

    private var contextMenuContent: some View {
        CardContextMenu(
            item: item,
            itemID: item.id,
            isPinned: item.isPinned,
            allowPinning: allowPinning,
            readOnly: readOnly,
            assignedPinboardIDs: assignedPinboardIDs,
            pinboards: pinboards,
            lockedPinboardIDs: lockedPinboardIDs,
            onPaste: onPaste,
            onPastePlainText: onPastePlainText,
            onTogglePin: onTogglePin,
            onCopy: onCopy,
            onConvertType: onConvertType,
            onMoveToPinboard: onMoveToPinboard,
            onCreatePinboard: onCreatePinboard,
            onEdit: onEdit,
            onRename: onRename,
            onDelete: onDelete
        )
    }

    private var rightInfoColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 4) {
                if item.isPinned && allowPinning {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                }

                Text(rightSideMetric)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Image(systemName: typeIcon)
                Circle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3, height: 3)
                Text(timeAgoShort)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var leadingVisual: some View {
        ZStack {
            if let pinboard = primaryAssignedPinboard {
                if let signKind = PinboardSignResolver.resolve(pinboard.iconName) {
                    pinboardSignView(signKind)
                }
            } else {
                AppIconView(
                    bundleID: item.sourceAppBundleID,
                    appName: item.sourceAppName,
                    iconData: item.sourceAppIconData,
                    size: 19
                )
            }
        }
        .frame(width: sideBarWidth, alignment: .center)
        .frame(maxHeight: .infinity)
        .zIndex(10) // Ensure sidebar is above background banner
    }

    @ViewBuilder
    private func pinboardSignView(_ signKind: PinboardSignKind) -> some View {
        switch signKind {
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(sideBarContentColor)
                .shadow(color: sideBarContentShadowColor, radius: 1, y: 0.4)
        case .text(let token):
            Text(token)
                .font(.system(size: 15))
                .foregroundStyle(sideBarContentColor)
                .shadow(color: sideBarContentShadowColor, radius: 1, y: 0.4)
        }
    }

    private var accessibilityLabel: String {
        "\(titleText). \(subtitle ?? "")"
    }

    private var titleView: some View {
        Group {
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular))
                    .focused($isFocused)
                    .onSubmit {
                        onCommitRename(item, editTitle)
                    }
                    .onAppear {
                        editTitle = item.customTitle ?? titleText
                        isFocused = true
                    }
            } else {
                Text(titleText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(textPrimaryColor)
                    .lineLimit(3)
                    .shadow(color: textShadowColor, radius: 2, x: 0, y: 1)
            }
        }
    }

    private var rowBackground: some View {
        ZStack(alignment: .leading) {
            cardShape
                .fill(
                    colorScheme == .dark
                        ? Color(.sRGB, white: 0.04, opacity: 0.72)
                        : Color(.sRGB, white: 0.96, opacity: 0.9)
                )
            
            // Ambient inner gradient on the content part
            if let pinboardColor {
                contentBackgroundShape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: pinboardColor.opacity(colorScheme == .dark ? 0.35 : 0.25), location: 0),
                                .init(color: pinboardColor.opacity(colorScheme == .dark ? 0.15 : 0.10), location: 0.5),
                                .init(color: pinboardColor.opacity(0.02), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.leading, sideBarWidth)
            }
            
            // Image / URL / Color Banner layer
            if hasBannerLayer {
                bannerLayer
            }

            Rectangle()
                .fill(sideBarColor)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.1 : 0.25),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                            Color.clear
                        ],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                    .frame(width: 4)
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .frame(width: sideBarWidth)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    private var contentBackgroundShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: 0,
                bottomTrailing: cardCornerRadius,
                topTrailing: cardCornerRadius
            ),
            style: .continuous
        )
    }

    private var hasBannerLayer: Bool {
        item.itemTypeValue == .image || item.itemTypeValue == .url || item.itemTypeValue == .color
    }

    private var textPrimaryColor: Color {
        hasBannerLayer ? .white : .primary
    }

    private var textSecondaryColor: Color {
        hasBannerLayer ? .white.opacity(0.8) : .secondary
    }

    private var textShadowColor: Color {
        hasBannerLayer ? .black.opacity(0.8) : .clear
    }

    @ViewBuilder
    private var bannerLayer: some View {
        Group {
            if item.itemTypeValue == .image, let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if item.itemTypeValue == .url {
                URLBannerPreview(
                    linkPreviewResult: linkPreviewResult,
                    host: urlHost,
                    path: urlPath,
                    isCompact: true
                )
                .task(id: linkPreviewTaskID) {
                    refreshLinkPreview()
                }
            } else if item.itemTypeValue == .color, let color = colorItemBackground {
                ZStack(alignment: .leading) {
                    color
                    if let hex = normalizedColorHex, let foreground = colorItemForeground {
                        Text(hex.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                            .padding(.leading, 12) // ensure it's not sticking strictly to the sidebar left bound
                    }
                }
            }
        }
        .frame(width: 120, alignment: .leading) // Fixed width for banner
        .frame(maxHeight: .infinity)
        // Offset by sidebar width to place it exactly after the color strip
        .offset(x: sideBarWidth)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.6), // delay gradient fade
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: sideBarWidth)
        )
    }
    
    var linkPreviewTaskID: String {
        let url =
            normalizedPrimaryURL?.absoluteString
            ?? (item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let bannerPath =
            item.linkPreview?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bannerURL =
            item.linkPreview?.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(url)|\(bannerPath)|\(bannerURL)"
    }

    private var contentSignature: ContentSignature {
        ContentSignature(item: item)
    }

    private var sideBarColor: Color {
        if let pinboardColor {
            return pinboardColor
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.24)
    }

    private var sideBarContentColor: Color {
        sideBarIsDark ? .white.opacity(0.95) : .black.opacity(0.78)
    }

    private var sideBarContentShadowColor: Color {
        sideBarIsDark ? .black.opacity(0.26) : .white.opacity(0.12)
    }

    private var sideBarIsDark: Bool {
        let color = sideBarNSColor.usingColorSpace(.sRGB) ?? sideBarNSColor
        let luminance = (0.2126 * color.redComponent)
            + (0.7152 * color.greenComponent)
            + (0.0722 * color.blueComponent)
        return luminance < 0.58
    }

    private var sideBarNSColor: NSColor {
        if let pinboard = primaryAssignedPinboard {
            return NSColor(hex: pinboard.colorHex)
        }
        return colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.24)
    }

    private var primaryAssignedPinboard: Pinboard? {
        let assigned = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        return assigned.sorted(by: { $0.sortOrder < $1.sortOrder }).first
    }

    private var pinboardColor: Color? {
        guard let pinboard = primaryAssignedPinboard else {
            return nil
        }
        return Color(hex: pinboard.colorHex, fallback: .gray)
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            cardShape
                .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
        }
    }

    private var assignedPinboardIDs: Set<UUID> {
        let assigned = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        return Set(assigned.map(\.id))
    }

    var normalizedColorHex: String? {
        guard item.itemTypeValue == .color, let text = item.primaryText else { return nil }
        return MartenHexColor.normalizedHex(from: text)
    }

    var colorItemBackground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return Color(hex: hex, fallback: .gray)
    }

    var colorItemForeground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return MartenHexColor.foregroundColor(forNormalizedHex: hex)
    }

    private var titleText: String {
        if let customTitle = item.customTitle, !customTitle.isEmpty {
            return customTitle
        }
        let text = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
        return typeLabel
    }

    private var subtitle: String? {
        if let appName = item.sourceAppName, !appName.isEmpty {
            return appName
        }
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
            return bundleID
        }
        return nil
    }

    private var timeAgoShort: String {
        Self.compactTimeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
            .replacingOccurrences(of: " ago", with: "")
            .replacingOccurrences(of: "in ", with: "")
    }

    private var typeLabel: String {
        switch item.itemTypeValue {
        case .text: return "Text"
        case .richText: return "Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "URL"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }

    private var typeCompactLabel: String {
        switch item.itemTypeValue {
        case .richText:
            return "Text"
        case .mixed:
            return "Mixed"
        default:
            return typeLabel
        }
    }

    private var rightSideMetric: String {
        switch item.itemTypeValue {
        case .text, .richText, .code:
            let count = item.primaryText?.count ?? 0
            return "\(count) ch"
        case .color:
            return "Color"
        case .url:
            let content = urlHost.isEmpty ? (item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : urlHost
            var displayUrl = content
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
            
            // Remove trailing slash if present
            if displayUrl.hasSuffix("/") {
                displayUrl.removeLast()
            }
                
            if displayUrl.count > 30 {
                displayUrl = String(displayUrl.prefix(30)) + "..."
            }
            return displayUrl
        default:
            if item.byteCount > 0 {
                return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
            }
            return typeLabel
        }
    }

    private var typeIcon: String {
        switch item.itemTypeValue {
        case .text: return "textformat"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .code: return "chevron.left.slash.chevron.right"
        case .color: return "paintpalette"
        case .mixed: return "square.stack"
        }
    }

    private func handleTap() {
        let now = Date()
        if let lastTapTime, now.timeIntervalSince(lastTapTime) < 0.3 {
            onDoubleTap(item)
            self.lastTapTime = nil
        } else {
            onTap(item)
            self.lastTapTime = now
        }
    }
}

private struct ContentSignature: Equatable {
    let primaryText: String?
    let thumbnailPath: String?
    let representationAssetSignature: String
    let customTitle: String?
    let linkPreviewImagePath: String?
    let modifiedAt: Date
    let itemType: ItemType

    init(item: ClipItem) {
        primaryText = item.primaryText
        thumbnailPath = item.thumbnailPath
        representationAssetSignature = (item.representations ?? [])
            .map { representation in
                let assetRef = representation.assetRef?.uuidString ?? "none"
                let fileExtension = representation.fileExtension?.lowercased() ?? "none"
                return "\(assetRef).\(fileExtension)"
            }
            .sorted()
            .joined(separator: ",")
        customTitle = item.customTitle
        linkPreviewImagePath = item.linkPreview?.imagePath
        modifiedAt = item.modifiedAt
        itemType = item.itemTypeValue
    }
}

