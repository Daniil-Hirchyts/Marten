import SwiftUI

struct PinboardTab: View {
    let title: String
    let colorHex: String?
    let isSelected: Bool
    var minWidth: CGFloat? = nil
    let action: () -> Void
    
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex, fallback: .gray))
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            .frame(minWidth: minWidth, minHeight: 20)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
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
