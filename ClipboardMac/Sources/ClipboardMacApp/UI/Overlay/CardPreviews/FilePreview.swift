import AppKit
import SwiftUI

struct FilePreview: View {
    let icon: NSImage?
    let name: String
    let size: String?
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background card
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.05)
                )
            
            // Icon
            VStack(spacing: 0) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(
                            colorScheme == .dark
                                ? Color.white.opacity(0.6)
                                : Color.black.opacity(0.3)
                        )
                }
            }
        }
    }
}
