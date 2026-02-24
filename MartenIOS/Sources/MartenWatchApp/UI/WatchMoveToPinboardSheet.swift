import SwiftUI

struct WatchMoveToPinboardSheet: View {
    @Bindable var container: MartenWatchContainer
    let item: WatchClipSummary

    @Environment(\.dismiss) private var dismiss
    @State private var isMoving = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                if container.customPinboards.isEmpty {
                    Text("No pinboards available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .watchCard(prominence: .subtle)
                } else {
                    ForEach(container.customPinboards) { pinboard in
                        Button {
                            move(to: pinboard.id)
                        } label: {
                            HStack(spacing: 8) {
                                Text(pinboard.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if currentItem.pinboardIDs.contains(pinboard.id) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .watchCard(prominence: currentItem.pinboardIDs.contains(pinboard.id) ? .accent : .normal)
                        .disabled(isMoving)
                    }
                }
            }
            .padding(.horizontal, WatchVisualSystem.outerPadding)
            .padding(.bottom, WatchVisualSystem.outerPadding)
        }
        .navigationTitle("Move")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isMoving)
            }
        }
    }

    private var currentItem: WatchClipSummary {
        container.items.first(where: { $0.id == item.id }) ?? item
    }

    private func move(to pinboardID: UUID) {
        guard !isMoving else { return }
        isMoving = true

        Task { @MainActor in
            let moved = await container.moveItem(itemID: currentItem.id, to: pinboardID)
            isMoving = false
            if moved {
                dismiss()
            }
        }
    }
}
