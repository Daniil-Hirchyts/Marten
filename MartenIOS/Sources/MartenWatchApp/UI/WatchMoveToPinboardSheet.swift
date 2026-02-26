import SwiftUI

struct WatchMoveToPinboardSheet: View {
    @Bindable var container: MartenWatchContainer
    let item: WatchClipSummary

    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false

    var body: some View {
        List {
            if container.customPinboards.isEmpty {
                Text("No pinboards available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .watchCard(prominence: .subtle)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(container.customPinboards) { pinboard in
                    let color = Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor)
                    let isCurrent = currentItem.pinboardIDs.contains(pinboard.id)
                    let state = pinboardState(for: pinboard)

                    Button {
                        move(to: pinboard.id)
                    } label: {
                        HStack(spacing: 10) {
                            WatchPinboardIcon(iconName: pinboard.iconName, tint: color)

                            HStack(spacing: 5) {
                                Text(pinboard.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                if let state {
                                    Image(systemName: state.systemImage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(state.tint)
                                }
                            }

                            Spacer(minLength: 0)

                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, WatchVisualSystem.cardPadding)
                        .padding(.vertical, WatchVisualSystem.cardPadding + 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            color.opacity(isCurrent ? 0.6 : 0.3),
                                            color.opacity(isCurrent ? 0.4 : 0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                                .strokeBorder(color.opacity(isCurrent ? 0.72 : 0.48), lineWidth: 1)
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdating)
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Move")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isUpdating)
            }
        }
    }

    private var currentItem: WatchClipSummary {
        container.items.first(where: { $0.id == item.id }) ?? item
    }

    private func pinboardState(for pinboard: WatchPinboardSummary) -> (
        systemImage: String,
        tint: Color
    )? {
        if container.lockStateStore.isLocked(pinboard.id) {
            let isUnlocked = container.lockStateStore.canAccess(pinboard.id)
            return (isUnlocked ? "lock.open.fill" : "lock.fill", isUnlocked ? .orange : .secondary)
        }

        if pinboard.isShared {
            return ("person.2.fill", .secondary)
        }

        return nil
    }

    private func move(to pinboardID: UUID) {
        let isCurrent = currentItem.pinboardIDs.contains(pinboardID)
        guard !isUpdating else { return }
        isUpdating = true

        Task { @MainActor in
            let updated = await container.setItemPinboardMembership(
                itemID: currentItem.id,
                pinboardID: pinboardID,
                isMember: !isCurrent
            )
            isUpdating = false
            if updated {
                dismiss()
            }
        }
    }
}
