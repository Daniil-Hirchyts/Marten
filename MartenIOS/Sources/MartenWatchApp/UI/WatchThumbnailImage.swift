import ImageIO
import SwiftUI

struct WatchThumbnailImage: View {
    let path: String

    @State private var cgImage: CGImage?

    var body: some View {
        ZStack {
            WatchTransparencyGrid(squareSize: 8)
            
            Group {
                if let cgImage {
                    Image(decorative: cgImage, scale: 2.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: path) {
            cgImage = loadDownsampled(path: path, maxDimension: 200)
        }
    }

    private func loadDownsampled(path: String, maxDimension: CGFloat) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
