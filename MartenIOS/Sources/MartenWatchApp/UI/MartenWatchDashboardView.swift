import SwiftUI

struct MartenWatchDashboardView: View {
    @Bindable var container: MartenWatchContainer

    @State private var allItemsCount = 0
    @State private var pinboardItemCounts: [UUID: Int] = [:]

    var body: some View {
        List {
            allPinboardCard
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)

            ForEach(container.customPinboards) { pinboard in
                pinboardCard(for: pinboard)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Color.clear.frame(height: 56)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Pinboards")
        .refreshable {
            await container.refresh()
            await loadPinboardCounts()
        }
        .overlay(alignment: .bottomTrailing) {
            addClipboardButton
        }
        .task {
            await loadPinboardCounts()
        }
        .task(id: container.customPinboards) {
            await loadPinboardCounts()
        }
        .onAppear {
            Task {
                await loadPinboardCounts()
            }
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { container.lastOperationErrorMessage != nil },
                set: { _ in container.clearOperationError() }
            )
        ) {
            Button("OK") {
                container.clearOperationError()
            }
        } message: {
            Text(container.lastOperationErrorMessage ?? "Unknown error")
        }
    }

    private var allPinboardCard: some View {
        NavigationLink {
            WatchPinboardCardsView(container: container, pinboardID: nil, title: "All")
        } label: {
            pinboardCardContent(
                title: "All",
                iconName: "tray",
                statusIcon: nil,
                statusTint: nil,
                color: .gray,
                isSelected: container.selectedPinboardID == nil,
                itemCount: allItemsCount
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pinboardCard(for pinboard: WatchPinboardSummary) -> some View {
        let state = pinboardState(for: pinboard)
        let isLocked = container.lockStateStore.isLocked(pinboard.id) && !container.lockStateStore.canAccess(pinboard.id)

        if isLocked {
            Button {
                Task {
                    await container.selectPinboard(pinboard.id)
                    _ = await container.unlockSelectedPinboard()
                }
            } label: {
                pinboardCardContent(
                    title: pinboard.name,
                    iconName: pinboard.iconName,
                    statusIcon: state?.systemImage,
                    statusTint: state?.tint,
                    color: Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor),
                    isSelected: container.selectedPinboardID == pinboard.id,
                    itemCount: pinboardItemCounts[pinboard.id] ?? 0
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                WatchPinboardCardsView(container: container, pinboardID: pinboard.id, title: pinboard.name)
            } label: {
                pinboardCardContent(
                    title: pinboard.name,
                    iconName: pinboard.iconName,
                    statusIcon: state?.systemImage,
                    statusTint: state?.tint,
                    color: Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor),
                    isSelected: container.selectedPinboardID == pinboard.id,
                    itemCount: pinboardItemCounts[pinboard.id] ?? 0
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func pinboardCardContent(
        title: String,
        iconName: String?,
        statusIcon: String?,
        statusTint: Color?,
        color: Color,
        isSelected: Bool,
        itemCount: Int
    ) -> some View {
        HStack(spacing: 10) {
            WatchPinboardIcon(iconName: iconName, tint: color)

            HStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if let statusIcon, let statusTint {
                    Image(systemName: statusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
            }

            Spacer(minLength: 0)

            Text("\(itemCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, WatchVisualSystem.cardPadding)
        .padding(.vertical, WatchVisualSystem.cardPadding + 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(isSelected ? 0.6 : 0.3),
                            color.opacity(isSelected ? 0.4 : 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(isSelected ? 0.72 : 0.48), lineWidth: 1)
        )
        .contentShape(.rect)
    }

    private var addClipboardButton: some View {
        WatchFloatingTextFieldLinkActionButton(
            systemImage: "plus",
            accessibilityLabel: "Add clipboard item",
            prompt: "Type or dictate"
        ) { text in
            Task { @MainActor in
                _ = await container.createTextItem(text)
            }
        }
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

    private func loadPinboardCounts() async {
        let allCount = (try? await container.queryService.items(query: "", pinboardID: nil, limit: 5000).count) ?? 0
        var counts: [UUID: Int] = [:]
        for pinboard in container.customPinboards {
            let count = (try? await container.queryService.items(query: "", pinboardID: pinboard.id, limit: 5000).count)
                ?? 0
            counts[pinboard.id] = count
        }

        allItemsCount = allCount
        pinboardItemCounts = counts
    }
}

