import MartenCore
import SwiftUI

struct ItemCardView: View {
    let item: ClipItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let dragPayload: ItemDragPayload
    let onTap: () -> Void
    let onCopy: () -> Void
    let onCopyPlainText: () -> Void
    let onPreview: () -> Void
    let onShare: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    var isInDragPile: Bool = false
    var dragPileCount: Int = 0

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

    private var resolvedPresentation: ItemCardPresentation {
        presentation ?? ItemCardPresentation(item: item)
    }
    
    private var headerBackgroundColor: Color? {
        guard let colorHex = resolvedPresentation.primaryPinboardColorHex,
              ColorHex.normalizedHex(from: colorHex) != nil else {
            return nil
        }
        return Color(hex: colorHex, fallback: .gray)
    }
    
    private var headerTextColor: Color {
        headerBackgroundColor != nil ? .white : .primary
    }
    
    private var cardAccentColor: Color? {
        headerBackgroundColor?.opacity(0.3)
    }

    var body: some View {
        let pres = resolvedPresentation

        cardContent(pres)
            .contentShape(.rect(cornerRadius: 18))
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(MartenAnimation.quick, value: isPressed)
            .sensoryFeedback(.selection, trigger: isSelected)
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.3, perform: {
                // Enter selection mode on long press
                if !isSelectionMode {
                    onTap()
                }
            }, onPressingChanged: { pressing in
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
                    Label("Move to Pinboard", systemImage: "tray.full")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .draggable(dragPayload)
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
            .accessibilityLabel(
                "\(pres.title), \(pres.footerSource), \(pres.footerDate)"
                    + (isSelected ? ", selected" : "")
            )
            .accessibilityHint("Double tap to open")
            .accessibilityAddTraits(.isButton)
    }

    private func cardContent(_ pres: ItemCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(pres)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 18
                    )
                    .fill(headerBackgroundColor?.opacity(0.96) ?? Color.clear)
                )
            
            VStack(alignment: .leading, spacing: 6) {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                cardFooter(pres)
            }
            .padding(14)
            .padding(.top, 6)
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isSelected || isInDragPile
                        ? Color.accentColor
                        : (cardAccentColor ?? Color.white.opacity(0.14)),
                    lineWidth: isSelected || isInDragPile ? 3 : 1.5
                )
        )
        .overlay(alignment: .topTrailing) {
            if dragPileCount > 1 {
                Text("\(dragPileCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(
            color: (cardAccentColor ?? Color.black).opacity(0.08),
            radius: 4,
            x: 0,
            y: 2
        )
        .aspectRatio(1, contentMode: .fit)
    }

    private func cardHeader(_ pres: ItemCardPresentation) -> some View {
        HStack(alignment: .center, spacing: 6) {
            typeIcon
                .font(.caption)
                .foregroundStyle(
                    headerBackgroundColor != nil 
                        ? Color.white.opacity(0.9) 
                        : Color(platformColor: .platformTertiaryLabel)
                )
                .frame(width: 14, alignment: .center)

            Text(pres.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(headerTextColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let colorHex = pres.primaryPinboardColorHex,
               let sign = pres.primaryPinboardSign {
                PinboardIndicator(
                    colorHex: colorHex,
                    sign: sign,
                    size: 24,
                    showBorder: headerBackgroundColor == nil
                )
            }

            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(
                        isSelected 
                            ? Color.accentColor 
                            : (headerBackgroundColor != nil ? Color.white.opacity(0.7) : Color(platformColor: .platformTertiaryLabel))
                    )
                    .animation(MartenAnimation.quick, value: isSelected)
            }
        }
    }

    private func cardFooter(_ pres: ItemCardPresentation) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if let accentColor = cardAccentColor {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 4, height: 4)
                }
                
                Text(pres.footerSource)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(pres.footerDate)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var typeIcon: some View {
        Group {
            switch resolvedPresentation.previewKind {
            case .text: Image(systemName: "doc.text")
            case .richText: Image(systemName: "doc.richtext")
            case .code: Image(systemName: "chevron.left.forwardslash.chevron.right")
            case .link: Image(systemName: "link")
            case .image: Image(systemName: "photo")
            case .file: Image(systemName: "doc")
            case .color: Image(systemName: "paintpalette")
            case .mixed: Image(systemName: "square.stack")
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch resolvedPresentation.previewKind {
        case .text, .richText:
            Text(resolvedPresentation.snippet ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(resolvedPresentation.snippet ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var imagePreview: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.5))

                if let thumbnailImage {
                    #if canImport(UIKit)
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity)
                    #elseif canImport(AppKit)
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity)
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary.opacity(0.3))
                        .shimmer()
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.quaternary)
                        }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let linkPreviewImage {
                #if canImport(UIKit)
                Image(uiImage: linkPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 70)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
                #elseif canImport(AppKit)
                Image(nsImage: linkPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 70)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
                #endif
            }

            if let host = resolvedPresentation.urlHost {
                Text(host)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            if let snippet = resolvedPresentation.snippet {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var filePreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedPresentation.fileName ?? "File")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if let fileSize = resolvedPresentation.fileSize {
                    Text(fileSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var colorPreview: some View {
        let hex = resolvedPresentation.colorHex ?? "#808080"
        let background = Color(hex: hex, fallback: .gray)
        let foreground = ColorHex.foregroundColor(
            for: ColorHex.normalizedHex(from: hex) ?? "#808080"
        )

        return RoundedRectangle(cornerRadius: 10)
            .fill(background)
            .frame(height: 50)
            .overlay {
                Text(resolvedPresentation.snippet ?? hex)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
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
