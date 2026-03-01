import AppKit
import SwiftUI

struct URLBannerPreview: View {
    let linkPreviewResult: LinkPreviewImageResult?
    let host: String
    let path: String
    let isCompact: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch linkPreviewResult {
                case .banner(let image):
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                case .favicon(let image):
                    placeholderBackground
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                case nil:
                    placeholderBackground
                    Image(systemName: "link")
                        .font(.system(size: isCompact ? 30 : 38, weight: .light))
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

    private var placeholderBackground: some View {
        Rectangle()
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(DesignTokens.Opacity.backgroundSubtle)
                    : Color.black.opacity(0.05)
            )
    }
}
