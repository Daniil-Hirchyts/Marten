import SwiftUI

struct FilePreview: View {
    let name: String
    let size: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            if let size {
                Text(size)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
