import AppKit
import SwiftUI

struct ImagePreview: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                ZStack {
                    TransparencyGrid(squareSize: 8)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }
}
