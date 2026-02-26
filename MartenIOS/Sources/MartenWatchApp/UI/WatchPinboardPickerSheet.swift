import SwiftUI

struct WatchPinboardPickerSheet: View {
    @Bindable var container: MartenWatchContainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                WatchSectionTitle(title: "Pinboards", detail: "\(container.customPinboards.count + 1)")
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)

                pinboardRow(
                    title: "All",
                    subtitle: "Every card",
                    iconName: "tray",
                    isLocked: false,
                    isSelected: container.selectedPinboardID == nil
                ) {
                    container.selectPinboard(nil)
                    dismiss()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)

                if container.customPinboards.isEmpty {
                    Text("No custom pinboards yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .watchCard(prominence: .subtle)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(container.customPinboards) { pinboard in
                        pinboardRow(
                            title: pinboard.name,
                            subtitle: pinboard.isShared ? "Shared" : "Private",
                            iconName: pinboard.iconName ?? "pin",
                            isLocked: container.lockStateStore.isLocked(pinboard.id)
                                && !container.lockStateStore.canAccess(pinboard.id),
                            isSelected: container.selectedPinboardID == pinboard.id
                        ) {
                            container.selectPinboard(pinboard.id)
                            dismiss()
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Pinboards")
        }
    }

    @ViewBuilder
    private func pinboardRow(
        title: String,
        subtitle: String,
        iconName: String,
        isLocked: Bool,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .watchCard(prominence: isSelected ? .accent : .normal)
        .padding(.vertical, 4)
    }
}
