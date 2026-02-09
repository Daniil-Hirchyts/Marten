import SwiftUI

struct URLPreview: View {
    let host: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host)
                .font(.system(size: 11, weight: .semibold))
            Text(path)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}
