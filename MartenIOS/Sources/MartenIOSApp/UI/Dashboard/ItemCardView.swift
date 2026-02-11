import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct ItemCardView: View {
    let item: ClipItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let dragPayload: ItemDragPayload
    let onTap: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    @State private var thumbnailImage: PlatformImage?
    @State private var linkPreviewImage: PlatformImage?
    @State private var presentation: ItemCardPresentation?
    @State private var cachedImageTaskID: String?

    private var resolvedPresentation: ItemCardPresentation {
        presentation ?? ItemCardPresentation(item: item)
    }

    var body: some View {
        let pres = resolvedPresentation

        MartenGlassSurface(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(pres.title)
                    .font(.headline)
                    .lineLimit(1)

                previewContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                footer
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isSelected ? Color.accentColor : .clear,
                    lineWidth: isSelected ? 2 : 0
                )
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                onShare()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                onMove()
            } label: {
                Label("Move to Pinboard", systemImage: "tray.full")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
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

    private var previewContent: some View {
        Group {
            switch resolvedPresentation.previewKind {
            case .text, .richText:
                Text(resolvedPresentation.snippet ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            case .code:
                Text(resolvedPresentation.snippet ?? "")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(minHeight: 78)
    }

    private var imagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.05))

            if let thumbnailImage {
                #if canImport(UIKit)
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                #elseif canImport(AppKit)
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                #endif
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let linkPreviewImage {
                #if canImport(UIKit)
                Image(uiImage: linkPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 78)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
                #elseif canImport(AppKit)
                Image(nsImage: linkPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 78)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
                #endif
            }

            if let host = resolvedPresentation.urlHost {
                Text(host)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            if let path = resolvedPresentation.urlPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let snippet = resolvedPresentation.snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var filePreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedPresentation.fileName ?? "File")
                    .font(.subheadline)
                    .lineLimit(1)

                if let fileSize = resolvedPresentation.fileSize {
                    Text(fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var colorPreview: some View {
        let hex = resolvedPresentation.colorHex ?? "#808080"
        let background = Color(hex: hex, fallback: .gray)
        let foreground = ColorHex.foregroundColor(for: ColorHex.normalizedHex(from: hex) ?? "#808080")

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(background)

            Text(resolvedPresentation.snippet ?? hex)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(resolvedPresentation.footerSource)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("•")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(resolvedPresentation.footerDate)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Text(resolvedPresentation.footerTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

    private func loadImageFromDisk(path: String) async -> PlatformImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                #if canImport(UIKit)
                let image = UIImage(contentsOfFile: path)
                #elseif canImport(AppKit)
                let image = NSImage(contentsOfFile: path)
                #endif
                continuation.resume(returning: image)
            }
        }
    }
}
