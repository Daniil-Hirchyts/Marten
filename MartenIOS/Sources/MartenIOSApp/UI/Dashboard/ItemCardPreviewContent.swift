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
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
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

        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            Text(presentation.snippet ?? hex)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryTextColor: Color {
        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    private var secondaryTextColor: Color {
        return colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
    }
}
