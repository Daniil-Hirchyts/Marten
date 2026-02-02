import SwiftUI

struct PinboardTab: View {
    let title: String
    var iconName: String? = nil
    let colorHex: String?
    var trailingIconName: String? = nil
    let isSelected: Bool
    var minWidth: CGFloat? = nil
    var maxWidth: CGFloat? = nil
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textColor)
                } else if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex, fallback: .gray))
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let trailingIconName {
                    Image(systemName: trailingIconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.95))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.18), value: trailingIconName)
                }
            }
            .frame(minWidth: minWidth, minHeight: 20)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(backgroundView)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var textColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.85)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .glassStyle(shape: .capsule, isProminent: isSelected)
        } else {
            fallbackBackgroundColor
        }
    }

    private var fallbackBackgroundColor: Color {
        let opacity: CGFloat
        if isSelected {
            opacity = DesignTokens.Opacity.backgroundStrong
        } else if isHovering {
            opacity = DesignTokens.Opacity.backgroundMedium
        } else {
            opacity = DesignTokens.Opacity.backgroundSubtle
        }

        return colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color.black.opacity(opacity)
    }
}
