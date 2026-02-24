import SwiftUI

struct MartenWatchDashboardView: View {
    @Bindable var container: MartenWatchContainer

    @State private var isShowingQuickAdd = false
    @State private var allItemsCount = 0
    @State private var pinboardItemCounts: [UUID: Int] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                allPinboardCard

                ForEach(container.customPinboards) { pinboard in
                    pinboardCard(for: pinboard)
                }
            }
            .padding(.horizontal, WatchVisualSystem.outerPadding)
            .padding(.bottom, 56)
        }
        .navigationTitle("Pinboards")
        .refreshable {
            await container.refresh()
            await loadPinboardCounts()
        }
        .sheet(isPresented: $isShowingQuickAdd) {
            WatchQuickAddSheet(container: container)
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
                iconName: "tray.2",
                statusTitle: nil,
                statusIcon: nil,
                statusTint: nil,
                color: .gray,
                isSelected: container.selectedPinboardID == nil,
                itemCount: allItemsCount,
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pinboardCard(for pinboard: WatchPinboardSummary) -> some View {
        let state = pinboardState(for: pinboard)

        NavigationLink {
            WatchPinboardCardsView(container: container, pinboardID: pinboard.id, title: pinboard.name)
        } label: {
            pinboardCardContent(
                title: pinboard.name,
                iconName: pinboard.iconName,
                statusTitle: state.title,
                statusIcon: state.systemImage,
                statusTint: state.tint,
                color: Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor),
                isSelected: container.selectedPinboardID == pinboard.id,
                itemCount: pinboardItemCounts[pinboard.id] ?? 0,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    private func pinboardCardContent(
        title: String,
        iconName: String?,
        statusTitle: String?,
        statusIcon: String?,
        statusTint: Color?,
        color: Color,
        isSelected: Bool,
        itemCount: Int,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 10) {
            WatchPinboardIcon(iconName: iconName, tint: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if let statusTitle, let statusIcon, let statusTint {
                    WatchMetadataPill(title: statusTitle, systemImage: statusIcon, tint: statusTint)
                }
            }

            Spacer(minLength: 0)

            Text("\(itemCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(WatchVisualSystem.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                .fill(color.opacity(isSelected ? 0.4 : 0.26))
        )
        .overlay(
            RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(isSelected ? 0.72 : 0.48), lineWidth: 1)
        )
        .contentShape(.rect)
    }

    private var addClipboardButton: some View {
        WatchFloatingGlassActionButton(
            systemImage: "plus",
            accessibilityLabel: "Add clipboard item"
        ) {
            isShowingQuickAdd = true
        }
    }

    private func pinboardState(for pinboard: WatchPinboardSummary) -> (
        title: String,
        systemImage: String,
        tint: Color
    ) {
        let isLocked = container.lockStateStore.isLocked(pinboard.id)
            && !container.lockStateStore.canAccess(pinboard.id)

        if isLocked {
            return ("Locked", "lock.fill", .orange)
        }

        if pinboard.isShared {
            return ("Shared", "person.2.fill", .blue)
        }

        return ("Private", "lock.open.fill", .secondary)
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

private struct WatchPinboardIcon: View {
    let iconName: String?
    let tint: Color

    var body: some View {
        Group {
            if let iconName,
                iconName.containsEmoji,
                !iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(iconName)
                    .font(.body)
            } else {
                Image(systemName: iconName ?? "tray")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.16), in: Circle())
    }
}

private extension String {
    var containsEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }
}
