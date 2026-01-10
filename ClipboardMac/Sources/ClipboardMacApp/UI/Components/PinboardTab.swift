import SwiftUI

struct PinboardTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
