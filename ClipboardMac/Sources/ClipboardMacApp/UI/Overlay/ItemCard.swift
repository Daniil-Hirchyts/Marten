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
    let pinboardColors: [Color]

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

        // Cache pinboard colors
        self.pinboardColors = Self.computePinboardColors(for: item)
    }

    private static func computeTypeLabel(for itemType: ItemType) -> String {
        switch itemType {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "URL"
        case .code: return "Code"
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
        case .mixed:
            return text.isEmpty ? "Mixed" : text
        }
    }

    private static func computePreviewText(for item: ClipItem, itemType: ItemType) -> String? {
        guard let text = item.primaryText, !text.isEmpty else { return nil }
        switch itemType {
        case .text, .richText, .code:
            return text
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
                let url = URL(fileURLWithPath: text)
                let size =
                    item.byteCount > 0
                    ? ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
                    : nil
                if let size {
                    return [url.lastPathComponent, size]
                }
                return [url.lastPathComponent]
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
        default:
            return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        }
    }

    private static func computePinboardColors(for item: ClipItem) -> [Color] {
        let pinboards = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        let sorted = pinboards.sorted { $0.sortOrder < $1.sortOrder }
        var seen = Set<String>()
        return sorted.compactMap { pinboard in
            guard !seen.contains(pinboard.colorHex) else { return nil }
            seen.insert(pinboard.colorHex)
            return Color(hex: pinboard.colorHex, fallback: .gray)
        }
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
        fileName: String,
        fileSizeText: String?,
        previewText: String?
    ) -> some View {
        Group {
            switch itemType {
            case .image:
                ImagePreview(image: thumbnailImage)
            case .url:
                URLPreview(host: urlHost, path: urlPath)
            case .file:
                FilePreview(name: fileName, size: fileSizeText)
            case .code:
                CodePreview(text: previewText ?? "")
            case .richText, .text:
                TextPreview(text: previewText ?? "")
            case .mixed:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .frame(width: 72, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
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
    @FocusState private var isFocused: Bool

    /// Cached properties to avoid recalculating on every render
    private var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                headerView
                contentPreviewView
                Spacer(minLength: 0)
                footerView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(cardBackground)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            if isSelected {
                checkmarkOverlay
            }
        }
        .onAppear {
            cachedProps = CachedItemProperties(item: item)
        }
        .onChange(
            of: item.objectID,
            perform: { _ in
                cachedProps = CachedItemProperties(item: item)
            }
        )
        .onReceive(item.objectWillChange) { _ in
            DispatchQueue.main.async {
                cachedProps = CachedItemProperties(item: item)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
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
                Text(cached.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            if !cached.pinboardColors.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(cached.pinboardColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                    }
                }
            } else if item.sourceAppBundleID != nil {
                AppIconView(bundleID: item.sourceAppBundleID, size: 16)
            }

            if showPinIndicator, item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .padding(.leading, 4)
            }
        }
    }

    private var contentPreviewView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if cached.shouldShowPrimaryTitle {
                Text(cached.primaryTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let preview = cached.previewText {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            } else if let details = cached.detailLines {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var footerView: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            Text(cached.statsLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1)
            )
    }

    private var checkmarkOverlay: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .padding(8)
            .transition(.scale.combined(with: .opacity))
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
