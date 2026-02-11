import MartenCore
import SwiftUI

struct PinboardSwitcherView: View {
    let pinboards: [Pinboard]
    let lockStateStore: PinboardLockStateStore
    @Binding var selectedPinboardID: UUID?
    let onManage: () -> Void
    let onDropPayload: (ItemDragPayload, Pinboard?) -> Bool

    @State private var activeDropTarget: DropTarget?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                MartenGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        pinboardChip(
                            title: "All",
                            colorHex: nil,
                            isSelected: selectedPinboardID == nil,
                            isLocked: false,
                            dropTarget: .all,
                            pinboard: nil
                        ) {
                            selectedPinboardID = nil
                        }

                        ForEach(displayPinboards, id: \.objectID) { pinboard in
                            pinboardChip(
                                title: pinboardDisplayName(pinboard),
                                colorHex: pinboard.colorHex,
                                isSelected: selectedPinboardID == pinboard.id,
                                isLocked: lockStateStore.isLocked(pinboard.id),
                                dropTarget: .pinboard(pinboard.id),
                                pinboard: pinboard
                            ) {
                                selectedPinboardID = pinboard.id
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                Spacer()
                MartenGlassButton(action: onManage) {
                    Label("Manage Pinboards", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("ios.dashboard.pinboards.manage")
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }

    private var displayPinboards: [Pinboard] {
        let system = pinboards
            .filter(\.isSystemMarten)
            .sorted { $0.sortOrder < $1.sortOrder }

        let custom = pinboards
            .filter { !$0.isSystemMarten }
            .sorted { $0.sortOrder < $1.sortOrder }

        return system + custom
    }

    private func pinboardDisplayName(_ pinboard: Pinboard) -> String {
        if pinboard.isSystemMarten {
            return "Clipboard History"
        }
        return pinboard.name
    }

    private func pinboardChip(
        title: String,
        colorHex: String?,
        isSelected: Bool,
        isLocked: Bool,
        dropTarget: DropTarget,
        pinboard: Pinboard?,
        action: @escaping () -> Void
    ) -> some View {
        let chip = MartenGlassButton(action: action) {
            HStack(spacing: 6) {
                if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex, fallback: .gray))
                        .frame(width: 10, height: 10)
                }

                Text(title)
                    .font(.subheadline.weight(.medium))

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        activeDropTarget == dropTarget
                            ? Color.accentColor.opacity(0.26)
                            : (isSelected ? Color.accentColor.opacity(0.18) : .clear)
                    )
            )
        }
        .accessibilityLabel(isLocked ? "\(title), locked" : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        return dropEnabledChip(
            chip,
            isDropEnabled: !isLocked,
            dropTarget: dropTarget,
            pinboard: pinboard
        )
    }

    @ViewBuilder
    private func dropEnabledChip<Content: View>(
        _ content: Content,
        isDropEnabled: Bool,
        dropTarget: DropTarget,
        pinboard: Pinboard?
    ) -> some View {
        if isDropEnabled {
            content.dropDestination(
                for: ItemDragPayload.self,
                action: { payloads, _ in
                    guard let payload = payloads.first else { return false }
                    let handled = onDropPayload(payload, pinboard)
                    if handled {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
                            activeDropTarget = nil
                        }
                    }
                    return handled
                },
                isTargeted: { isTargeted in
                    withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
                        if isTargeted {
                            activeDropTarget = dropTarget
                        } else if activeDropTarget == dropTarget {
                            activeDropTarget = nil
                        }
                    }
                }
            )
        } else {
            content
        }
    }
}

private enum DropTarget: Hashable {
    case all
    case pinboard(UUID)
}
