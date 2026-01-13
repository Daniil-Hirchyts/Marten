import AppKit
import ClipboardCore
import SwiftUI

struct ItemCard: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let isSelected: Bool
    let isEditing: Bool
    let badgeIndex: Int?
    let isDropTarget: Bool
    let showPinIndicator: Bool
    let allowPinning: Bool
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
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                // 1. Header
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
                            .onAppear {
                                editTitle = item.customTitle ?? typeLabel
                                isFocused = true
                            }
                    } else {
                        Text(displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Right Side Icon
                    if !pinboardColors.isEmpty {
                        // Show Pinboard Dots if pinned/organized
                        HStack(spacing: 3) {
                            ForEach(Array(pinboardColors.enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    } else if let icon = sourceAppIcon {
                        // Show App Icon if default clipboard
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    }
                    
                    if showPinIndicator, item.isPinned {
                         Image(systemName: "pin.fill")
                             .font(.system(size: 11, weight: .semibold))
                             .foregroundStyle(.yellow)
                             .padding(.leading, 4)
                    }
                }

                // 2. Content Preview
                VStack(alignment: .leading, spacing: 4) {
                    // Show primary text title if it's meaningful (e.g. File Name, URL)
                    // For plain text, we skip title if it just duplicates preview
                    if shouldShowPrimaryTitle {
                        Text(primaryTitle)
                             .font(.system(size: 12, weight: .medium))
                             .foregroundStyle(.primary)
                             .lineLimit(1)
                    }

                    if let preview = previewText {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    } else if let details = detailLines {
                        ForEach(details, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer(minLength: 0)

                // 3. Footer (Time & Stats)
                HStack(alignment: .center, spacing: 8) {
                    Text(timeAgo)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                    
                    Text(statsLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1)
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }

        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            let now = Date()
            if let lastTime = lastTapTime, now.timeIntervalSince(lastTime) < 0.3 {
                onDoubleTap()
                lastTapTime = nil // Reset
            } else {
                onTap()
                lastTapTime = now
            }
        }
        .contextMenu {
            CardContextMenu(
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

    private var shouldShowPrimaryTitle: Bool {
        // Show title for Files and URLs, hide for Text if it duplicates preview
        switch item.itemTypeValue {
        case .file, .url: return true
        default: return false
        }
    }
    
    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
    
    private var statsLabel: String {
        switch item.itemTypeValue {
        case .text, .richText, .code:
            let count = item.primaryText?.count ?? 0
            return "\(count) chars"
        default:
            return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        }
    }

    private var preview: some View {
        Group {
            switch item.itemTypeValue {
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

    private var sourceAppIcon: NSImage? {
        guard let bundleID = item.sourceAppBundleID else { return nil }
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }

    private var thumbnailImage: NSImage? {
        guard let path = item.thumbnailPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var primaryTitle: String {
        let text = item.primaryText ?? "Untitled"
        switch item.itemTypeValue {
        case .file:
            let fileURL = URL(fileURLWithPath: text)
            if fileURL.isFileURL {
                return fileURL.lastPathComponent
            }
            return text.isEmpty ? "File" : text
        case .url:
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

    private var detailText: String? {
        switch item.itemTypeValue {
        case .url:
            if let text = item.primaryText, let url = URL(string: text), let host = url.host {
                return url.path.isEmpty ? host : "\(host)\(url.path)"
            }
            return "URL"
        case .file:
            if let text = item.primaryText, !text.isEmpty {
                return text
            }
            return "File"
        case .image:
            if item.byteCount > 0 {
                return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
            }
            return "Image"
        case .richText, .code, .mixed, .text:
            return nil
        }
    }

    private var previewText: String? {
        guard let text = item.primaryText, !text.isEmpty else { return nil }
        switch item.itemTypeValue {
        case .text, .richText, .code:
            return text
        default:
            return nil
        }
    }

    private var detailLines: [String]? {
        switch item.itemTypeValue {
        case .url:
            if let text = item.primaryText, let url = URL(string: text) {
                let host = url.host ?? "URL"
                let path = url.path.isEmpty ? "/" : url.path
                return [host, path]
            }
            return nil
        case .file:
            if let text = item.primaryText, !text.isEmpty {
                let url = URL(fileURLWithPath: text)
                let size = item.byteCount > 0 ? ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file) : nil
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

    private var urlHost: String {
        guard let text = item.primaryText, let url = URL(string: text) else { return "URL" }
        return url.host ?? "URL"
    }

    private var urlPath: String {
        guard let text = item.primaryText, let url = URL(string: text) else { return "/" }
        return url.path.isEmpty ? "/" : url.path
    }

    private var fileName: String {
        guard let text = item.primaryText, !text.isEmpty else { return "File" }
        return URL(fileURLWithPath: text).lastPathComponent
    }

    private var fileSizeText: String? {
        guard item.byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
    }

    private var sourceText: String? {
        guard let source = item.sourceAppName, !source.isEmpty else { return nil }
        return "From \(source)"
    }

    private var displayTitle: String {
        if let customTitle = item.customTitle, !customTitle.isEmpty {
            return customTitle
        }
        return typeLabel
    }

    private var typeLabel: String {
        switch item.itemTypeValue {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "URL"
        case .code:
            return "Code"
        case .mixed:
            return "Mixed"
        }
    }

    private var typeIcon: String {
        switch item.itemTypeValue {
        case .text:
            return "textformat"
        case .richText:
            return "doc.richtext"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .url:
            return "link"
        case .code:
            return "chevron.left.slash.chevron.right"
        case .mixed:
            return "square.stack"
        }
    }

    private var pinboardColors: [Color] {
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
