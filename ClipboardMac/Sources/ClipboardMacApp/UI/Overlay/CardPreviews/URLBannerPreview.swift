import AppKit
import SwiftUI

struct URLBannerPreview: View {
    let image: NSImage?
    let host: String
    let path: String
    let isCompact: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(DesignTokens.Opacity.backgroundSubtle)
                            : Color.black.opacity(0.05)
                    )

                Image(systemName: "link")
                    .font(.system(size: isCompact ? 30 : 38, weight: .light))
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color.white.opacity(0.35)
                            : Color.black.opacity(0.25)
                    )
            }

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(image == nil ? 0.25 : 0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(host)
                    .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(path)
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, isCompact ? 8 : 10)
            .padding(.vertical, isCompact ? 6 : 8)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
