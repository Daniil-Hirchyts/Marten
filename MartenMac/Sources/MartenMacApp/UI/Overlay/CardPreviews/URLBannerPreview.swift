import AppKit
import SwiftUI

struct URLBannerPreview: View {
    let image: NSImage?
    let host: String
    let path: String
    let isCompact: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
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
        }
        .frame(maxWidth: .infinity)
    }
}
