import AppKit
import ClipboardCore
import SwiftUI
import UniformTypeIdentifiers
import LinkPresentation

struct OverlayItemPreview: View {
    let item: ClipItem
    let allowPinning: Bool
    let pinboards: [Pinboard]
    let onEdit: () -> Void
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onDelete: () -> Void

    private let store = ClipItemStore()

    @State private var image: NSImage?
    @State private var fileIcon: NSImage?
    @State private var urlBannerImage: NSImage?
    @State private var lastLoadedURLBannerPath: String?
    @State private var lastFetchedURLBannerURLString: String?
    @State private var cachedProps: CachedItemProperties?
    @State private var rotationAngle: Angle = .zero
    @State private var styledRichTextPreview: AttributedString?

    private var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.objectID) { _, _ in
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.primaryText) { _, _ in
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.modifiedAt) { _, _ in
            refreshCachedProperties()
            loadAssetsIfNeeded()
            refreshStyledTextPreview()
        }
        .onChange(of: item.linkPreview?.imagePath) { _, _ in
            loadURLBannerIfNeeded()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(typeTitle)
                    .font(.system(size: 13, weight: .semibold))
                if let title = headerSubtitle {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                actionIconButton(
                    title: "Paste",
                    systemImage: "doc.on.clipboard",
                    action: onPaste
                )
                actionIconButton(
                    title: "Paste as Plain Text",
                    systemImage: "doc.plaintext",
                    action: onPastePlainText
                )
                actionIconButton(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    action: onCopy
                )
                actionIconButton(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    action: shareItem
                )
                if allowPinning {
                    actionIconButton(
                        title: item.isPinned ? "Unpin" : "Pin",
                        systemImage: item.isPinned ? "pin.slash" : "pin",
                        action: onTogglePin
                    )
                }
                quickAddToPinboardMenu
                actionIconButton(
                    title: "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )
            }

            actionTextButton(
                title: "Edit",
                action: onEdit
            )
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.itemTypeValue {
        case .image:
            imageContent
        case .url:
            urlContent
        case .file:
            fileContent
        case .color:
            colorContent
        case .mixed:
            mixedContent
        case .code:
            scrollableText(
                item.plainTextContent ?? item.primaryText ?? "",
                monospaced: true
            )
        case .richText:
            if let styledRichTextPreview {
                scrollableStyledText(styledRichTextPreview)
            } else {
                scrollableText(
                    item.plainTextContent ?? item.primaryText ?? "",
                    monospaced: false
                )
            }
        case .text:
            scrollableText(
                item.plainTextContent ?? item.primaryText ?? "",
                monospaced: false
            )
        }
    }

    private var imageContent: some View {
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

    private var urlContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Banner section - prominent and standalone
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

            // Title and summary section - if available
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

            // URL metadata section - subtle card
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

    private var fileContent: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            
            // File icon - clean and simple like cards
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

            // File name below icon
            if let name = nonEmptyText(fileDisplayName) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            // File size - subtle
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

    private var colorContent: some View {
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

    private var mixedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Icon and info section
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

            // Text preview section if available
            if let mixedText = mixedTextPreview {
                scrollableText(mixedText, monospaced: false)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func scrollableText(_ text: String, monospaced: Bool) -> some View {
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

    private func scrollableStyledText(_ text: AttributedString) -> some View {
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

    @ViewBuilder
    private func actionIconButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        if let role {
            Button(role: role, action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 10))
            .help(title)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 10))
            .help(title)
            .accessibilityLabel(title)
        }
    }
    
    private func actionTextButton(
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 10))
        .accessibilityLabel(title)
    }

    private var quickAddToPinboardMenu: some View {
        Menu {
            if pinboards.isEmpty {
                Text("No pinboards")
            } else {
                ForEach(pinboards) { pinboard in
                    let isAssigned = assignedPinboardIDs.contains(pinboard.id)
                    Button {
                        onMoveToPinboard(pinboard)
                    } label: {
                        HStack(spacing: 8) {
                            pinboardSelectionCircle(
                                colorHex: pinboard.colorHex,
                                isFilled: isAssigned,
                                size: 10
                            )
                            Text(pinboard.name)
                        }
                    }
                }
            }

            Divider()

            Button("New Pinboard...") {
                onCreatePinboard()
            }
        } label: {
            Group {
                if let colorHex = primaryAssignedPinboardColorHex {
                    pinboardSelectionCircle(colorHex: colorHex, isFilled: true, size: 13)
                } else {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.75), lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveGlassBackground(shape: .circle)
        .help("Quick add to pinboards")
        .accessibilityLabel("Quick add to pinboards")
    }

    private func pinboardSelectionCircle(colorHex: String, isFilled: Bool, size: CGFloat) -> some View
    {
        let color = Color(hex: colorHex, fallback: .gray)
        return ZStack {
            Circle()
                .strokeBorder(color.opacity(0.95), lineWidth: 1.5)
            if isFilled {
                Circle()
                    .fill(color)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
    }

    private var assignedPinboards: [Pinboard] {
        (item.pinboards?.filter { !$0.isSystemClipboard } ?? []).sorted {
            $0.sortOrder < $1.sortOrder
        }
    }

    private var primaryAssignedPinboardColorHex: String? {
        assignedPinboards.first?.colorHex
    }

    private var assignedPinboardIDs: Set<UUID> {
        Set(assignedPinboards.map(\.id))
    }

    private var headerSubtitle: String? {
        if let customTitle = nonEmptyText(item.customTitle) {
            return customTitle
        }
        if cached.shouldShowPrimaryTitle {
            return nonEmptyText(cached.primaryTitle)
        }
        return nil
    }

    private var typeTitle: String {
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

    private var normalizedPrimaryURL: URL? {
        guard let raw = nonEmptyText(item.primaryText) else { return nil }
        if raw.localizedCaseInsensitiveContains("://") {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }

    private var urlHost: String {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else {
            return "URL"
        }
        return url.host ?? "URL"
    }

    private var urlPath: String {
        guard item.itemTypeValue == .url, let url = normalizedPrimaryURL else {
            return "/"
        }
        return url.path.isEmpty ? "/" : url.path
    }

    private var urlDisplayText: String {
        if let normalizedPrimaryURL {
            return normalizedPrimaryURL.absoluteString
        }
        return item.primaryText ?? ""
    }

    private var filePath: String? {
        guard item.itemTypeValue == .file else { return nil }
        return filePathFromRepresentations()
    }

    private var fileDisplayName: String {
        if let path = filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let text = nonEmptyText(item.primaryText) {
            return text
        }
        return "File"
    }

    private var fileSizeText: String? {
        guard item.byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
    }

    private var imageMetadata: String? {
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

    private var imageFileName: String? {
        guard item.itemTypeValue == .image, let path = filePathFromRepresentations() else {
            return nil
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var imageResolution: String? {
        guard item.itemTypeValue == .image, let image else { return nil }
        return "\(Int(image.size.width))×\(Int(image.size.height))"
    }

    private var normalizedColor: String? {
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

    private var mixedRepresentationLabels: [String] {
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

    private var mixedTextPreview: String? {
        nonEmptyText(item.plainTextContent ?? item.primaryText)
    }

    private func shareItem() {
        let items = shareItems
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }

        let picker = NSSharingServicePicker(items: items)
        guard
            let window = NSApp.keyWindow ?? NSApp.mainWindow,
            let contentView = window.contentView
        else {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = contentView.convert(windowPoint, from: nil)
        let shareRect = NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1)
        picker.show(relativeTo: shareRect, of: contentView, preferredEdge: .maxY)
    }

    private var shareItems: [Any] {
        var items: [Any] = []

        switch item.itemTypeValue {
        case .file:
            if let filePath {
                items.append(URL(fileURLWithPath: filePath))
            }
        case .url:
            if let normalizedPrimaryURL {
                items.append(normalizedPrimaryURL)
            }
        case .image:
            if let image {
                items.append(image)
            } else if let path = filePathFromRepresentations() ?? nonEmptyText(item.thumbnailPath) {
                items.append(URL(fileURLWithPath: path))
            }
        case .mixed:
            if let filePath = filePathFromRepresentations() {
                items.append(URL(fileURLWithPath: filePath))
            }
            if let normalizedPrimaryURL {
                items.append(normalizedPrimaryURL)
            }
        default:
            break
        }

        if let text = nonEmptyText(item.plainTextContent ?? item.primaryText) {
            items.append(text)
        }

        return items
    }

    private func representationLabel(for kind: RepresentationKind) -> String {
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

    private func nonEmptyText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func refreshCachedProperties() {
        cachedProps = CachedItemProperties(item: item)
    }

    private func refreshStyledTextPreview() {
        guard item.itemTypeValue == .richText else {
            styledRichTextPreview = nil
            return
        }

        guard let styled = item.styledTextContentWithoutTextColor else {
            styledRichTextPreview = nil
            return
        }

        styledRichTextPreview = try? AttributedString(styled, including: \.appKit)
    }

    private func loadAssetsIfNeeded() {
        loadImageIfNeeded()
        loadFileIconIfNeeded()
        loadURLBannerIfNeeded()
    }

    private func loadURLBannerIfNeeded() {
        guard item.itemTypeValue == .url else {
            urlBannerImage = nil
            lastLoadedURLBannerPath = nil
            return
        }

        guard
            let path = item.linkPreview?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            urlBannerImage = nil
            lastLoadedURLBannerPath = nil
            return
        }

        if lastLoadedURLBannerPath == path {
            return
        }
        lastLoadedURLBannerPath = path

        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOfFile: path)
            DispatchQueue.main.async {
                urlBannerImage = img
            }
        }
    }

    private func fetchURLBannerIfNeeded() async {
        guard item.itemTypeValue == .url else { return }

        guard let url = normalizedPrimaryURL, let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return
        }
        let urlString = url.absoluteString

        if urlBannerImage != nil {
            lastFetchedURLBannerURLString = urlString
            return
        }

        if lastFetchedURLBannerURLString == urlString {
            return
        }

        let provider = LPMetadataProvider()
        let metadata: LPLinkMetadata
        do {
            metadata = try await provider.startFetchingMetadata(for: url)
        } catch {
            return
        }

        let itemProvider = metadata.imageProvider ?? metadata.iconProvider
        guard let itemProvider else { return }

        let image: NSImage?
        do {
            image = try await loadNSImage(from: itemProvider)
        } catch {
            return
        }

        guard let image else { return }
        await MainActor.run {
            if urlBannerImage == nil {
                urlBannerImage = image
            }
        }
    }

    private func loadNSImage(from provider: NSItemProvider) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image = object as? NSImage else {
                    continuation.resume(throwing: NSError(domain: "URLBannerPreview", code: 1))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func loadImageIfNeeded() {
        guard item.itemTypeValue == .image else {
            image = nil
            return
        }

        if let path = nonEmptyText(item.thumbnailPath) {
            DispatchQueue.global(qos: .userInitiated).async {
                let img = NSImage(contentsOfFile: path)
                DispatchQueue.main.async {
                    image = img
                }
            }
            return
        }

        let representations = item.representations ?? []
        let imageData: [Data] = representations.compactMap { rep in
            let kind = rep.kindValue
            guard kind == .png || kind == .jpeg || kind == .tiff else {
                return nil
            }
            return rep.binaryData
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for data in imageData {
                if let img = NSImage(data: data) {
                    DispatchQueue.main.async { image = img }
                    return
                }
            }
            DispatchQueue.main.async { image = nil }
        }
    }

    private func loadFileIconIfNeeded() {
        guard item.itemTypeValue == .file, let path = filePathFromRepresentations() else {
            fileIcon = nil
            return
        }
        fileIcon = NSWorkspace.shared.icon(forFile: path)
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
    
    // MARK: - Image & File Actions
    
    private func rotateImage(direction: ImagePreview.RotationDirection) {
        guard let currentImage = image else {
            NSSound.beep()
            return
        }

        // Apply rotation to the image
        let rotationDegrees: Double = direction == .left ? -90 : 90
        let rotatedImage = rotateNSImage(currentImage, degrees: rotationDegrees)

        // Convert to PNG data
        guard let imageData = imageDataFrom(rotatedImage) else {
            NSSound.beep()
            return
        }

        // Save to store
        do {
            try store.updateImageData(objectID: item.objectID, imageData: imageData)
            // Update local image immediately
            image = rotatedImage
        } catch {
            NSSound.beep()
            print("Failed to save rotated image: \(error)")
        }
    }

    private func imageDataFrom(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    private func rotateNSImage(_ image: NSImage, degrees: Double) -> NSImage {
        let radians = CGFloat(degrees * .pi / 180.0)
        
        // Calculate new size after rotation
        let originalSize = image.size
        let rotatedWidth = abs(originalSize.width * CoreGraphics.cos(radians)) + abs(originalSize.height * CoreGraphics.sin(radians))
        let rotatedHeight = abs(originalSize.width * CoreGraphics.sin(radians)) + abs(originalSize.height * CoreGraphics.cos(radians))
        let newSize = NSSize(width: rotatedWidth, height: rotatedHeight)
        
        let rotatedImage = NSImage(size: newSize)
        rotatedImage.lockFocus()
        
        let transform = NSAffineTransform()
        transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        transform.rotate(byRadians: -radians)  // Negate to make positive = clockwise
        transform.translateX(by: -originalSize.width / 2, yBy: -originalSize.height / 2)
        transform.concat()
        
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        rotatedImage.unlockFocus()
        return rotatedImage
    }
    
    private func saveImageAs() {
        guard let image else {
            NSSound.beep()
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Image"
        savePanel.nameFieldStringValue = imageFileName ?? "image.png"
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.png, .jpeg, .tiff]
        savePanel.allowsOtherFileTypes = false

        // Use runModal for proper modal presentation
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            saveImage(image, to: url)
        }
    }
    
    private func saveImage(_ image: NSImage, to url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            NSSound.beep()
            return
        }
        
        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            fileType = .jpeg
        case "tif", "tiff":
            fileType = .tiff
        default:
            fileType = .png
        }
        
        guard let imageData = bitmapImage.representation(using: fileType, properties: [:]) else {
            NSSound.beep()
            return
        }
        
        do {
            try imageData.write(to: url)
        } catch {
            NSSound.beep()
            print("Failed to save image: \(error)")
        }
    }
    
    private func saveFileAs() {
        guard let sourcePath = filePath else {
            NSSound.beep()
            return
        }
        
        let sourceURL = URL(fileURLWithPath: sourcePath)
        
        let savePanel = NSSavePanel()
        savePanel.title = "Save File"
        savePanel.nameFieldStringValue = fileDisplayName
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                NSSound.beep()
                print("Failed to save file: \(error)")
            }
        }
    }
}
