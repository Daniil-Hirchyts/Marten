import AppKit
import MartenCore
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
        VStack(alignment: .leading, spacing: 0) {
            if let previewURL = previewableURL {
                URLInternalBrowserPreview(url: previewURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unable to preview this URL")
                        .font(.system(size: 14, weight: .semibold))
                    Text(urlDisplayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
                )
            }
        }
    }

    var fileContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let previewableFileURL {
                FileDocumentPreview(fileURL: previewableFileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    if let icon = fileIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 64, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }

                    Text("Preview unavailable for this file")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(fileDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)

                if let size = fileSizeText {
                    Text(size)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundSubtle))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var colorContent: some View {
        ColorPreview(hex: item.primaryText ?? "")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                                isLocked: isLocked,
                                colorScheme: colorScheme
                            ))
                        }
                    }
                }
            }

            Divider()

            Button {
                onCreatePinboard(item)
            } label: {
                Label("New Pinboard...", systemImage: "plus")
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
        (item.pinboards?.filter { !$0.isSystemMarten } ?? []).sorted {
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
        case .richText: "Text"
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

    var previewableURL: URL? {
        guard let normalizedPrimaryURL else { return nil }
        guard let scheme = normalizedPrimaryURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return normalizedPrimaryURL
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

    var previewableFileURL: URL? {
        guard let filePath else { return nil }
        let candidateURL: URL
        if let parsedURL = URL(string: filePath), parsedURL.isFileURL {
            candidateURL = parsedURL
        } else {
            candidateURL = URL(fileURLWithPath: filePath)
        }
        guard FileManager.default.fileExists(atPath: candidateURL.path) else { return nil }
        return candidateURL
    }

    var fileDisplayName: String {
        if let previewableFileURL {
            return previewableFileURL.lastPathComponent
        }
        if let path = filePath {
            if let parsedURL = URL(string: path), parsedURL.isFileURL {
                return parsedURL.lastPathComponent
            }
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
        guard item.itemTypeValue == .image else { return nil }

        let sources = (item.representations ?? []).sorted { $0.displayOrder < $1.displayOrder }.map {
            ImageResolutionResolver.Source(
                kind: $0.kindValue,
                binaryData: $0.binaryData,
                assetRef: $0.assetRef,
                fileExtension: $0.fileExtension,
                textData: $0.textData
            )
        }
        let thumbnailPath = item.thumbnailPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThumbnailPath: String? = {
            guard let thumbnailPath, !thumbnailPath.isEmpty else { return nil }
            return thumbnailPath
        }()

        return ImageResolutionResolver.resolve(from: sources, thumbnailPath: normalizedThumbnailPath)
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
        case .rtf: return "RTF"
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
