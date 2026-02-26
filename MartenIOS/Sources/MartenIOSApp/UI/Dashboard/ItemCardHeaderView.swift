import MartenCore
import SwiftUI

struct ItemCardHeaderView: View {
    let presentation: ItemCardPresentation
    let isSelectionMode: Bool
    let isSelected: Bool
    let allowPinning: Bool
    let isPinned: Bool
    let cardCornerRadius: CGFloat
    let cardPadding: CGFloat
    let headerMinHeight: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(headerTextColor)
                    .lineLimit(1)

                if let subtitle = presentation.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(headerTextColor.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let colorHex = presentation.primaryPinboardColorHex,
               let sign = presentation.primaryPinboardSign {
                PinboardIndicator(
                    colorHex: colorHex,
                    sign: sign,
                    size: 24,
                    showBorder: false
                )
            } else {
                SourceAppIconBadge(
                    bundleID: presentation.sourceAppBundleID,
                    appName: presentation.sourceAppDisplayName,
                    iconData: presentation.sourceAppIconData,
                    size: 24,
                    showBackground: false
                )
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            }

            if allowPinning, isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(headerTextColor.opacity(0.85))
            }

            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(isSelected ? .palette : .monochrome)
                    .foregroundStyle(
                        isSelected ? .white : headerTextColor.opacity(0.5),
                        isSelected ? Color.accentColor : headerTextColor.opacity(0.5)
                    )
                    .font(.title3)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(minHeight: headerMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: cardCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cardCornerRadius
                )
                .fill(.ultraThinMaterial)

                UnevenRoundedRectangle(
                    topLeadingRadius: cardCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cardCornerRadius
                )
                .fill(headerBackgroundColor)
            }
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: cardCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cardCornerRadius
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
        )
    }

    private var sourceIconDescriptor: SourceAppIconDescriptor {
        SourceAppIconDescriptor.resolve(
            bundleID: presentation.sourceAppBundleID,
            appName: presentation.sourceAppDisplayName
        )
    }

    private var headerBackgroundColor: Color {
        if let pinboardHex = presentation.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            // Full opacity color in light mode, slightly transparent in dark mode
            return Color(hex: normalized, fallback: .gray).opacity(colorScheme == .dark ? 0.85 : 1.0)
        }
        return Color.clear
    }

    private var headerTextColor: Color {
        if let pinboardHex = presentation.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            // Force white text in light mode for high contrast on solid bright colors
            return colorScheme == .dark ? ColorHex.foregroundColor(for: normalized) : .white
        }
        return .primary
    }
}
