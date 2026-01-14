import SwiftUI

struct PinboardTab: View {
    let title: String
    var iconName: String? = nil
    let colorHex: String?
    let isSelected: Bool
    var minWidth: CGFloat? = nil
    var maxWidth: CGFloat? = nil
    let action: () -> Void
    
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .medium)) // Slightly larger than text
                        .foregroundStyle(.white)
                } else if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex, fallback: .gray))
                        .frame(width: 8, height: 8)
                }


                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: minWidth, minHeight: 20)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.2)
        }
        if isHovering {
            return Color.white.opacity(0.12)
        }
        return Color.white.opacity(0.08)
    }
}
