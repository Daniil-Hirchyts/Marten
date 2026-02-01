import AppKit
import SwiftUI

struct FilePreview: View {
    let icon: NSImage?
    let name: String
    let size: String?

    var body: some View {
        VStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 22, weight: .semibold))
            }
        }
    }
}
