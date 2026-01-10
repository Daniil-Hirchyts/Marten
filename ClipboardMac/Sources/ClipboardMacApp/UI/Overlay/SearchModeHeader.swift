import SwiftUI

struct SearchModeHeader: View {
    let query: String
    let resultCount: Int
    let onClear: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Search")
                    .font(.system(size: 12, weight: .semibold))
                Text("“\(query)” · \(resultCount) results")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") {
                onClear()
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
}
