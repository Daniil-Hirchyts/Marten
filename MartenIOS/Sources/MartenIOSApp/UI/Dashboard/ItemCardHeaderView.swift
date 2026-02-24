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
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .lineLimit(1)

                if let subtitle = presentation.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(headerTextColor.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let colorHex = presentation.primaryPinboardColorHex,
               let sign = presentation.primaryPinboardSign {
                PinboardIndicator(
                    colorHex: colorHex,
                    sign: sign,
                    size: 20,
                    showBorder: false
                )
            } else {
                SourceAppIconBadge(
                    bundleID: presentation.sourceAppBundleID,
                    appName: presentation.sourceAppDisplayName,
                    iconData: presentation.sourceAppIconData,
                    size: 20,
                    showBackground: false
                )
            }

            if allowPinning, isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(headerTextColor.opacity(0.85))
            }

            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(
                        isSelected
                            ? Color.accentColor
                            : headerTextColor.opacity(0.72)
                    )
                    .animation(MartenAnimation.quick, value: isSelected)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, 8)
        .frame(minHeight: headerMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: cardCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cardCornerRadius
            )
            .fill(headerBackgroundColor)
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
            return Color(hex: normalized, fallback: .gray).opacity(0.96)
        }
        return sourceIconDescriptor.backgroundColor.opacity(0.94)
    }

    private var headerTextColor: Color {
        if let pinboardHex = presentation.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            return ColorHex.foregroundColor(for: normalized)
        }
        return sourceIconDescriptor.foregroundColor
    }
}
