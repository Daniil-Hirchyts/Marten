import AppKit
import ClipboardCore
import SwiftUI

struct ItemCard: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            preview

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(primaryTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                    }
                }

                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let details = detailLines {
                    ForEach(details, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let source = sourceText {
                    Text(source)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: typeIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(typeLabel)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .contextMenu {
            CardContextMenu(
                isPinned: item.isPinned,
                pinboards: pinboards,
                onTogglePin: onTogglePin,
                onCopy: onCopy,
                onMoveToPinboard: onMoveToPinboard,
                onCreatePinboard: onCreatePinboard,
                onDelete: onDelete
            )
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: typeIcon)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .frame(width: 52, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var detailText: String {
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
        case .richText:
            return "Rich text"
        case .code:
            return "Code snippet"
        case .mixed:
            return "Multiple items"
        case .text:
            return "Text"
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
}
