import AppKit
import ClipboardCore
import LinkPresentation
import SwiftUI

extension OverlayItemPreview {
    var imageContent: some View {
        VStack(alignment: .center, spacing: 16) {
            ImagePreview(
                image: image,
                onRotate: { direction in
                    rotateImage(direction: direction)
                },
                onSaveAs: {
                    saveImageAs()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let metadata = imageMetadata {
                Text(metadata)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
                    )
            }
        }
    }

    var urlContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            URLBannerPreview(
                image: urlBannerImage,
                host: urlHost,
                path: urlPath,
                isCompact: false
            )
            .aspectRatio(1.91, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task {
                await fetchURLBannerIfNeeded()
            }

            if let title = nonEmptyText(item.linkPreview?.title) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let summary = nonEmptyText(item.linkPreview?.summary) {
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Text(urlDisplayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
            )
        }
    }

    var fileContent: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            if let icon = fileIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 84, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            if let name = nonEmptyText(fileDisplayName) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            if let size = fileSizeText {
                Text(size)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var colorContent: some View {
        VStack(alignment: .center, spacing: 16) {
            ColorPreview(hex: item.primaryText ?? "")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let normalized = normalizedColor {
                Text(normalized)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
                    )
            }
        }
    }

    var mixedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Mixed content")
                        .font(.system(size: 17, weight: .semibold))

                    if !mixedRepresentationLabels.isEmpty {
                        Text(mixedRepresentationLabels.joined(separator: " • "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text("\(item.representations?.count ?? 0) representations")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }

            if let mixedText = mixedTextPreview {
                scrollableText(mixedText, monospaced: false)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    func scrollableText(_ text: String, monospaced: Bool) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return ScrollView {
            if trimmed.isEmpty {
                Text("No textual preview available")
                    .font(
                        monospaced
                            ? .system(size: 14, weight: .regular, design: .monospaced)
                            : .system(size: 14)
                    )
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
                    .padding(14)
            } else {
                Text(trimmed)
                    .font(
                        monospaced
                            ? .system(size: 14, weight: .regular, design: .monospaced)
                            : .system(size: 14)
                    )
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
        )
    }

    func scrollableStyledText(_ text: AttributedString) -> some View {
        let trimmed = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)

        return ScrollView {
            if trimmed.isEmpty {
                Text("No textual preview available")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
                    .padding(14)
            } else {
                Text(text)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
        )
    }

    var quickAddToPinboardMenu: some View {
        Menu {
            if pinboards.isEmpty {
                Text("No pinboards")
            } else {
                ForEach(pinboards) { pinboard in
                    let isAssigned = assignedPinboardIDs.contains(pinboard.id)
                    let isLocked = lockedPinboardIDs.contains(pinboard.id)
                    Button {
                        onMoveToPinboard(item, pinboard)
                    } label: {
                        Label {
                            Text(pinboard.name)
                        } icon: {
                            Image(nsImage: NSImage.pinboardMenuIcon(
                                colorHex: pinboard.colorHex,
                                sign: pinboard.iconName,
                                size: 14,
                                isAssigned: isAssigned,
                                isLocked: isLocked
                            ))
                        }
                    }
                }
            }

            Divider()

            Button("New Pinboard...") {
                onCreatePinboard(item)
            }
        } label: {
            PinboardMenuLabel(
                primaryAssignedPinboardColorHex: primaryAssignedPinboardColorHex,
                primaryAssignedPinboardIconName: primaryAssignedPinboardIconName
            )
        }
        .buttonStyle(.plain)
        .help("Quick add to pinboards")
        .accessibilityLabel("Quick add to pinboards")
    }

    func pinboardSelectionIndicator(
        colorHex: String,
        iconName: String?,
        isAssigned: Bool,
        size: CGFloat
    )
        -> some View
    {
        PinboardIndicator(
            colorHex: colorHex,
            sign: iconName,
            size: size,
            isAssigned: isAssigned
        )
    }

    var assignedPinboards: [Pinboard] {
        (item.pinboards?.filter { !$0.isSystemClipboard } ?? []).sorted {
            $0.sortOrder < $1.sortOrder
        }
    }

    var primaryAssignedPinboardColorHex: String? {
        assignedPinboards.first?.colorHex
    }

    var primaryAssignedPinboardIconName: String? {
        assignedPinboards.first?.iconName
    }

    var assignedPinboardIDs: Set<UUID> {
        Set(assignedPinboards.map(\.id))
    }

    var headerSubtitle: String? {
        if let customTitle = nonEmptyText(item.customTitle) {
            return customTitle
        }
        if cached.shouldShowPrimaryTitle {
            return nonEmptyText(cached.primaryTitle)
        }
        return nil
    }

    var typeTitle: String {
        switch item.itemTypeValue {
        case .text: "Text"
        case .richText: "Rich Text"
        case .image: "Image"
        case .file: "File"
        case .url: "URL"
        case .code: "Code"
        case .color: "Color"
        case .mixed: "Mixed"
        }
    }

    var normalizedPrimaryURL: URL? {
        guard let raw = nonEmptyText(item.primaryText) else { return nil }
        if raw.localizedCaseInsensitiveContains("://") {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }

    var urlHost: String {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else {
            return "URL"
        }
        return url.host ?? "URL"
    }

    var urlPath: String {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else {
            return "/"
        }
        return url.path.isEmpty ? "/" : url.path
    }

    var urlDisplayText: String {
        if let normalizedPrimaryURL {
            return normalizedPrimaryURL.absoluteString
        }
        return item.primaryText ?? ""
    }

    var filePath: String? {
        guard item.itemTypeValue == .file else { return nil }
        return filePathFromRepresentations()
    }

    var fileDisplayName: String {
        if let path = filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let text = nonEmptyText(item.primaryText) {
            return text
        }
        return "File"
    }

    var fileSizeText: String? {
        guard item.byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
    }

    var imageMetadata: String? {
        var parts: [String] = []
        if let name = imageFileName {
            parts.append(name)
        }
        if let resolution = imageResolution {
            parts.append(resolution)
        }
        if let fileSizeText {
            parts.append(fileSizeText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var imageFileName: String? {
        guard item.itemTypeValue == .image, let path = filePathFromRepresentations() else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var imageResolution: String? {
        guard item.itemTypeValue == .image, let image else { return nil }
        return "\(Int(image.size.width))×\(Int(image.size.height))"
    }

    var normalizedColor: String? {
        guard item.itemTypeValue == .color, let raw = nonEmptyText(item.primaryText) else {
            return nil
        }

        var value = raw
        if value.lowercased().hasPrefix("0x") {
            value = String(value.dropFirst(2))
        }
        if value.hasPrefix("#") {
            value = String(value.dropFirst())
        }
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

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
            let end = cleaned.index(cleaned.startIndex, offsetBy: 6)
            return "#\(String(cleaned[..<end]))".uppercased()
        }
        return nil
    }

    var mixedRepresentationLabels: [String] {
        let sortedRepresentations = (item.representations ?? []).sorted {
            $0.displayOrder < $1.displayOrder
        }

        var seen = Set<String>()
        return sortedRepresentations.compactMap { rep in
            let label = representationLabel(for: rep.kindValue)
            guard seen.insert(label).inserted else { return nil }
            return label
        }
    }

    var mixedTextPreview: String? {
        nonEmptyText(item.plainTextContent ?? item.primaryText)
    }

    func representationLabel(for kind: RepresentationKind) -> String {
        switch kind {
        case .plainText: return "Plain Text"
        case .rtf: return "Rich Text"
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        case .fileURL: return "File URL"
        case .url: return "URL"
        case .custom: return "Custom"
        }
    }

    func nonEmptyText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PinboardMenuLabel: View {
    let primaryAssignedPinboardColorHex: String?
    let primaryAssignedPinboardIconName: String?
    
    @State private var isHovering = false

    var body: some View {
        Group {
            if let colorHex = primaryAssignedPinboardColorHex {
                PinboardIndicator(
                    colorHex: colorHex,
                    sign: primaryAssignedPinboardIconName,
                    size: 16,
                    isAssigned: true
                )
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
        )
        .onHover { isHovering = $0 }
    }
}
