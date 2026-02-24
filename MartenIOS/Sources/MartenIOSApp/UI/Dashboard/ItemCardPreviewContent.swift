import MartenCore
import SwiftUI

struct ItemCardPreviewContent: View {
    let presentation: ItemCardPresentation
    #if canImport(UIKit)
    let thumbnailImage: UIImage?
    let linkPreviewResult: LinkPreviewImageResult?
    #elseif canImport(AppKit)
    let thumbnailImage: NSImage?
    let linkPreviewResult: LinkPreviewImageResult?
    #endif

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch presentation.previewKind {
        case .text, .richText:
            Text(presentation.snippet ?? "")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(presentation.snippet ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(5)
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
            Text(presentation.snippet ?? "Mixed item")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var imagePreview: some View {
        ZStack {
            TransparencyGrid(squareSize: 10)

            if let thumbnailImage {
                #if canImport(UIKit)
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                #elseif canImport(AppKit)
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                #endif
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
            }
        }
    }

    private var linkPreview: some View {
        GeometryReader { geometry in
            ZStack {
                switch linkPreviewResult {
                case .banner(let image):
                    #if canImport(UIKit)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    #endif
                case .favicon(let image):
                    linkPreviewPlaceholderBackground
                    #if canImport(UIKit)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    #endif
                case nil:
                    linkPreviewPlaceholderBackground
                    Image(systemName: "link")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            colorScheme == .dark
                                ? Color.white.opacity(0.35)
                                : Color.black.opacity(0.25)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }

    private var linkPreviewPlaceholderBackground: some View {
        Rectangle()
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.05)
            )
    }

    private var filePreview: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            Image(systemName: "doc.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(secondaryTextColor)

            if let fileName = presentation.fileName {
                Text(fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var colorPreview: some View {
        let hex = presentation.colorHex ?? "#808080"
        let background = Color(hex: hex, fallback: .gray)
        let foreground = ColorHex.foregroundColor(
            for: ColorHex.normalizedHex(from: hex) ?? "#808080"
        )

        return Rectangle()
            .fill(background)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Text(presentation.snippet ?? hex)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
    }

    private var primaryTextColor: Color {
        if presentation.previewKind == .color,
           let colorHex = presentation.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalized)
        }
        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    private var secondaryTextColor: Color {
        if presentation.previewKind == .color,
           let colorHex = presentation.colorHex,
           let normalized = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalized).opacity(0.8)
        }
        return colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
    }
}
