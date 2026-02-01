import AppKit
import ClipboardCore
import SwiftUI

// MARK: - Cached Properties for Performance

/// Pre-computed properties from a ClipItem to avoid recalculating on every render
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
    let primaryPinboardName: String?
    let sourceLabel: String?

    init(item: ClipItem) {
        // Cache type-based properties
        let itemType = item.itemTypeValue

        self.typeLabel = Self.computeTypeLabel(for: itemType)
        self.typeIcon = Self.computeTypeIcon(for: itemType)
        self.shouldShowPrimaryTitle = itemType == .file || itemType == .url

        // Cache display title
        if let customTitle = item.customTitle, !customTitle.isEmpty {
            self.displayTitle = customTitle
        } else {
            self.displayTitle = self.typeLabel
        }

        // Cache primary title
        self.primaryTitle = Self.computePrimaryTitle(for: item, itemType: itemType)

        // Cache preview text
        self.previewText = Self.computePreviewText(for: item, itemType: itemType)

        // Cache detail lines
        self.detailLines = Self.computeDetailLines(for: item, itemType: itemType)

        // Cache stats label
        self.statsLabel = Self.computeStatsLabel(for: item, itemType: itemType)

        // Cache pinboard color and name
        let pinboardInfo = Self.computePrimaryPinboard(for: item)
        self.primaryPinboardColor = pinboardInfo.color
        self.primaryPinboardName = pinboardInfo.name

        // Cache source label (app name or bundle ID)
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
            if let text = item.primaryText, !text.isEmpty {
                let size =
                    item.byteCount > 0
                    ? ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
                    : nil
                if let size {
                    return [size]
                }
                return nil
            }
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

    private static func computePrimaryPinboard(for item: ClipItem) -> (color: Color?, name: String?)
    {
        let pinboards = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        let sorted = pinboards.sorted { $0.sortOrder < $1.sortOrder }
        guard let pinboard = sorted.first else { return (nil, nil) }
        return (Color(hex: pinboard.colorHex, fallback: .gray), pinboard.name)
    }

    private static func computeSourceLabel(for item: ClipItem) -> String? {
        // Prefer source app name, fallback to bundle ID
        if let appName = item.sourceAppName, !appName.isEmpty {
            return appName
        }
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
            // Extract app name from bundle ID (e.g., "com.apple.Safari" -> "Safari")
            let components = bundleID.split(separator: ".")
            if let lastComponent = components.last {
                return String(lastComponent)
            }
            return bundleID
        }
        return nil
    }
}

// MARK: - Preview Factory

/// Factory for creating preview views based on item type
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
                URLPreview(host: urlHost, path: urlPath)
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

// MARK: - ItemCard

struct ItemCard: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let isSelected: Bool
    let isEditing: Bool
    let badgeIndex: Int?
    let isDropTarget: Bool
    let showPinIndicator: Bool
    let allowPinning: Bool
    let isDragEnabled: Bool
    let cardSize: CGFloat
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onRename: () -> Void
    let onCommitRename: (String) -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var lastTapTime: Date?
    @State private var editTitle: String = ""
    @State private var cachedProps: CachedItemProperties?
    @StateObject private var appColorLoader = AppIconColorLoader()
    @State private var thumbnailImage: NSImage?
    @State private var fileIconImage: NSImage?
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// Cached properties to avoid recalculating on every render
    private var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    private var normalizedColorHex: String? {
        guard item.itemTypeValue == .color, let text = item.primaryText else { return nil }
        return ClipboardHexColor.normalizedHex(from: text)
    }

    private var colorItemBackground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return Color(hex: hex, fallback: .gray)
    }

    private var colorItemForeground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return ClipboardHexColor.foregroundColor(forNormalizedHex: hex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                headerView
                VStack(alignment: .leading, spacing: isCompactSize ? 8 : 10) {
                    contentPreviewView
                    Spacer(minLength: 0)
                    footerView
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, cardPadding)
                .padding(.top, isCompactSize ? 8 : 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cardBackground)
            .clipShape(cardShape)
            .overlay(selectionBorder)
            .contentShape(cardShape)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .onTapGesture {
            let now = Date()
            if let lastTime = lastTapTime, now.timeIntervalSince(lastTime) < 0.3 {
                onDoubleTap()
                lastTapTime = nil  // Reset
            } else {
                onTap()
                lastTapTime = now
            }
        }
        .onAppear {
            cachedProps = CachedItemProperties(item: item)
            appColorLoader.load(bundleID: item.sourceAppBundleID)
            refreshPreviewAssets()
        }
        .onChange(of: item.objectID) { _, _ in
            cachedProps = CachedItemProperties(item: item)
            appColorLoader.load(bundleID: item.sourceAppBundleID)
            refreshPreviewAssets()
        }
        .onChange(of: item.sourceAppBundleID) { newValue, _ in
            appColorLoader.load(bundleID: newValue)
        }
        .onReceive(item.objectWillChange) { _ in
            DispatchQueue.main.async {
                cachedProps = CachedItemProperties(item: item)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityIdentifier("overlay.itemCard.\(item.id.uuidString)")
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            CardContextMenu(
                itemID: item.id,
                isPinned: item.isPinned,
                allowPinning: allowPinning,
                assignedPinboardIDs: assignedPinboardIDs,
                pinboards: pinboards,
                onPaste: onPaste,
                onPastePlainText: onPastePlainText,
                onTogglePin: onTogglePin,
                onCopy: onCopy,
                onMoveToPinboard: onMoveToPinboard,
                onCreatePinboard: onCreatePinboard,
                onRename: onRename,
                onDelete: onDelete
            )
        }
    }

    private var assignedPinboardIDs: Set<UUID> {
        let assigned = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        return Set(assigned.map(\.id))
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .focused($isFocused)
                    .onSubmit {
                        onCommitRename(editTitle)
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

            if cached.primaryPinboardColor == nil,
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

    private var contentPreviewView: some View {
        Group {
            if item.itemTypeValue == .color, let hex = normalizedColorHex {
                // Color card: centered text in the content area
                VStack {
                    Spacer()
                    Text(hex)
                        .font(.system(size: colorFontSize, weight: .semibold))
                        .foregroundStyle(colorItemForeground ?? primaryTextColor)
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: isCompactSize ? 90 : 120)
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

    private var textDetailStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            if cached.shouldShowPrimaryTitle {
                Text(cached.primaryTitle)
                    .font(.system(size: contentFontSize, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
            }

            if let preview = cached.previewText {
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

    private var footerView: some View {
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

    private var cardBackground: some View {
        cardShape
            .fill(
                colorItemBackground
                    ?? (colorScheme == .dark
                        ? Color(.sRGB, white: 0.04, opacity: 0.72)
                        : Color(.sRGB, white: 0.96, opacity: 0.9))
            )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Spacing.cardCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            cardShape
                .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
        }
    }

    private var headerBackgroundShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: DesignTokens.Spacing.cardCornerRadius,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: DesignTokens.Spacing.cardCornerRadius
            ),
            style: .continuous
        )
    }

    private var headerBackground: some View {
        headerBackgroundShape
            .inset(by: headerBackgroundInset)
            .fill(headerBackgroundColor)
    }

    private var headerMinHeight: CGFloat {
        50
    }

    private var headerBackgroundInset: CGFloat {
        0
    }

    private var headerBackgroundColor: Color {
        // Color cards should NOT have colored headers - they use app/pinboard colors like other cards
        if let pinboardColor = cached.primaryPinboardColor {
            return pinboardColor.opacity(0.9)
        }
        if let appColor = appColorLoader.color {
            return Color(nsColor: appColor).opacity(0.9)
        }
        // Theme-aware fallback color
        return colorScheme == .dark
            ? Color(.sRGB, white: 0.2, opacity: 0.6)
            : Color(.sRGB, white: 0.85, opacity: 0.8)
    }

    // MARK: - Text Colors

    private var headerTextColor: Color {
        // Color cards use normal header text color (not based on color content)
        // If using vibrant pinboard or app color, white text works best
        if cached.primaryPinboardColor != nil || appColorLoader.color != nil {
            return Color.white
        }
        // For fallback gray background, use theme-aware text
        return colorScheme == .dark ? Color.white : Color.black
    }

    private var primaryTextColor: Color {
        if item.itemTypeValue == .color, let fg = colorItemForeground {
            return fg
        }
        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    private var secondaryTextColor: Color {
        if item.itemTypeValue == .color, let fg = colorItemForeground {
            return fg.opacity(0.8)
        }
        return colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
    }

    private var tertiaryTextColor: Color {
        if item.itemTypeValue == .color, let fg = colorItemForeground {
            return fg.opacity(0.7)
        }
        return colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private var headerSubtitle: String? {
        // Show pinboard name if available, otherwise show source app name
        if let pinboardName = cached.primaryPinboardName {
            return pinboardName
        }
        return cached.sourceLabel
    }

    // MARK: - Responsive Design

    /// Adjust spacing and sizing based on card size
    private var isCompactSize: Bool {
        cardSize < 280
    }

    private var cardPadding: CGFloat {
        isCompactSize ? 10 : 12
    }

    private var titleFontSize: CGFloat {
        isCompactSize ? 13 : 14
    }

    private var subtitleFontSize: CGFloat {
        isCompactSize ? 9 : 10
    }

    private var contentFontSize: CGFloat {
        isCompactSize ? 11 : 12
    }

    private var maxPreviewLines: Int {
        isCompactSize ? 3 : 5
    }

    private var shouldShowLeadingPreview: Bool {
        switch item.itemTypeValue {
        case .image, .file, .url, .mixed:
            return true
        default:
            return false
        }
    }

    private var fileSizeText: String? {
        guard item.byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
    }

    private var urlHost: String {
        guard item.itemTypeValue == .url, let text = item.primaryText, let url = URL(string: text)
        else {
            return "URL"
        }
        return url.host ?? "URL"
    }

    private var urlPath: String {
        guard item.itemTypeValue == .url, let text = item.primaryText, let url = URL(string: text)
        else {
            return "/"
        }
        return url.path.isEmpty ? "/" : url.path
    }

    private func refreshPreviewAssets() {
        refreshThumbnailImage()
        refreshFileIcon()
    }

    private func refreshThumbnailImage() {
        guard item.itemTypeValue == .image else {
            thumbnailImage = nil
            return
        }
        
        // Try to load from thumbnail path first
        if let path = item.thumbnailPath, !path.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = NSImage(contentsOfFile: path)
                DispatchQueue.main.async {
                    thumbnailImage = img
                }
            }
            return
        }
        
        // If no thumbnail path, try to load from image representations
        DispatchQueue.global(qos: .userInitiated).async {
            guard let reps = item.representations else {
                DispatchQueue.main.async {
                    thumbnailImage = nil
                }
                return
            }
            
            // Look for image representations
            for rep in reps {
                let kind = rep.kindValue
                if kind == .png || kind == .jpeg || kind == .tiff {
                    if let data = rep.binaryData, let img = NSImage(data: data) {
                        DispatchQueue.main.async {
                            thumbnailImage = img
                        }
                        return
                    }
                }
            }
            
            // If still no image, try to load from file URL
            if let fileRep = reps.first(where: { $0.kindValue == .fileURL }),
               let data = fileRep.textData,
               let path = String(data: data, encoding: .utf8) {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let img = NSImage(contentsOfFile: trimmed) {
                    DispatchQueue.main.async {
                        thumbnailImage = img
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                thumbnailImage = nil
            }
        }
    }

    private func refreshFileIcon() {
        guard item.itemTypeValue == .file, let filePath = filePathFromRepresentations() else {
            fileIconImage = nil
            return
        }
        fileIconImage = NSWorkspace.shared.icon(forFile: filePath)
    }

    private func filePathFromRepresentations() -> String? {
        guard let reps = item.representations else { return nil }
        guard let rep = reps.first(where: { $0.kindValue == .fileURL }) else { return nil }
        guard let data = rep.textData, let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var colorFontSize: CGFloat {
        isCompactSize ? 18 : 24
    }

    // MARK: - Non-cached Properties (need fresh data each render)

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    private var accessibilityLabelText: String {
        if let customTitle = item.customTitle, !customTitle.isEmpty {
            return customTitle
        }
        if cached.shouldShowPrimaryTitle {
            return "\(cached.displayTitle), \(cached.primaryTitle)"
        }
        if let snippet = previewSnippet {
            return "\(cached.displayTitle), \(snippet)"
        }
        return cached.displayTitle
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        parts.append(isSelected ? "Selected" : "Not selected")
        if item.isPinned {
            parts.append("Pinned")
        }
        parts.append(cached.statsLabel)
        return parts.joined(separator: ", ")
    }

    private var accessibilityHintText: String {
        var parts = ["Press to select"]
        if isDragEnabled {
            parts.append("Drag to move or reorder")
        }
        return parts.joined(separator: ". ")
    }

    private var previewSnippet: String? {
        guard let preview = cached.previewText else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "..."
        }
        return trimmed
    }

}

private enum ClipboardHexColor {
    static func normalizedHex(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var s = trimmed
        if s.lowercased().hasPrefix("0x") {
            s = String(s.dropFirst(2))
        }
        if s.hasPrefix("#") {
            s = String(s.dropFirst())
        }
        let cleaned = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleaned.count == 3 {
            let chars = Array(cleaned)
            return
                "#\(String(repeating: String(chars[0]), count: 2))\(String(repeating: String(chars[1]), count: 2))\(String(repeating: String(chars[2]), count: 2))"
                .uppercased()
        }
        if cleaned.count == 6 {
            return "#\(cleaned)".uppercased()
        }
        if cleaned.count == 8 {
            let start = cleaned.startIndex
            let end = cleaned.index(start, offsetBy: 6)
            return "#\(String(cleaned[start..<end]))".uppercased()
        }
        return nil
    }

    static func foregroundColor(forNormalizedHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return .white
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }
}

private struct QuickPasteBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.blue.opacity(0.9))
            .clipShape(Circle())
    }
}
