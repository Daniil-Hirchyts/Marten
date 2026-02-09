import SwiftUI

struct CodePreview: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}
