import MartenCore
import SwiftUI

struct DashboardTopBarView<PinboardMenuContent: View>: View {
    let isSelectionMode: Bool
    let selectedCount: Int
    let selectedPinboardTitle: String
    let currentPinboardItemCount: Int
    let selectedPinboard: Pinboard?
    let actionButtonSize: CGFloat
    let onToggleSelectionMode: () -> Void
    let onOpenSettings: () -> Void
    @ViewBuilder let pinboardMenuContent: (Pinboard) -> PinboardMenuContent

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                MartenGlassSurface(cornerRadius: 100, padding: 0, isInteractive: false) {
                    Text("\(selectedCount) Selected")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 24)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .transition(MartenAnimation.fadeScale)

                Spacer()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(selectedPinboardTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)

                    Text("\(currentPinboardItemCount)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.leading, 4)
                .transition(MartenAnimation.fadeScale)

                Spacer()

                if let pinboard = selectedPinboard, !pinboard.isSystemMarten {
                    Menu {
                        pinboardMenuContent(pinboard)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCircleBackground(isHighlighted: false)
                    .accessibilityLabel("Pinboard Options")
                    .accessibilityIdentifier("ios.dashboard.pinboardOptions")
                }
            }

            Button(action: onToggleSelectionMode) {
                Text(isSelectionMode ? "Done" : "Select")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 24)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassChipBackground(isHighlighted: isSelectionMode)
            .accessibilityLabel(isSelectionMode ? "Done" : "Select")
            .accessibilityIdentifier("ios.dashboard.selectMode")

            if !isSelectionMode {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: actionButtonSize, height: actionButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassCircleBackground(isHighlighted: false)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("ios.dashboard.settings")
                .transition(MartenAnimation.fadeScale)
            }
        }
    }
}

