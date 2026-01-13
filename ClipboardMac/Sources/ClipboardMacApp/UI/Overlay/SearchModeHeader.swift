import SwiftUI

struct SearchModeHeader: View {
    let query: String
    let resultCount: Int
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(resultCount) results for \"\(query)\"")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            
            Button("Clear") {
                onClear()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.blue)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Material.regular) // Use Material for glass effect
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.bottom, 4) // Spacing from content
    }
}
