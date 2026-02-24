import SwiftUI

struct WatchSettingsSheet: View {
    @Bindable var container: MartenWatchContainer

    @Environment(\.dismiss) private var dismiss
    @State private var totalCardsCount: Int?
    @State private var isLoadingCount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: WatchVisualSystem.sectionSpacing) {
                    syncSection
                    pinboardsSection
                    appSection
                }
                .padding(.horizontal, WatchVisualSystem.outerPadding)
                .padding(.bottom, WatchVisualSystem.outerPadding)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadTotalCardsCount()
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchSectionTitle(title: "Sync", detail: syncStatusLabel)

            LabeledContent("Status", value: syncStatusLabel)

            if let lastSyncDate = container.syncCoordinator?.lastSyncDate {
                LabeledContent(
                    "Last Sync",
                    value: lastSyncDate.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let syncErrorText {
                Text(syncErrorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await container.triggerSyncNow()
                    await loadTotalCardsCount()
                }
            } label: {
                HStack(spacing: 6) {
                    if container.isRunningSyncAction {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(container.isRunningSyncAction ? "Syncing" : "Sync Now")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(container.isRunningSyncAction || container.syncCoordinator == nil)
        }
        .font(.caption)
        .watchCard(prominence: .subtle)
    }

    private var pinboardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchSectionTitle(title: "Pinboards", detail: "\(container.customPinboards.count + 1)")

            LabeledContent("Selected", value: container.selectedPinboardTitle)
            LabeledContent("Shared", value: "\(sharedPinboardsCount)")
            LabeledContent("Locked", value: "\(lockedPinboardsCount)")
            LabeledContent("Cards", value: cardsCountLabel)

            Button("Refresh Data") {
                Task {
                    await container.refresh()
                    await loadTotalCardsCount()
                }
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
        .watchCard(prominence: .subtle)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchSectionTitle(title: "App", detail: nil)

            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
        }
        .font(.caption)
        .watchCard(prominence: .subtle)
    }

    private var syncStatusLabel: String {
        guard let syncCoordinator = container.syncCoordinator else {
            return "Unavailable"
        }

        switch syncCoordinator.status {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .error:
            return "Error"
        }
    }

    private var syncErrorText: String? {
        guard let syncCoordinator = container.syncCoordinator else {
            return nil
        }

        guard case .error(let error) = syncCoordinator.status else {
            return nil
        }

        return error.errorDescription
    }

    private var sharedPinboardsCount: Int {
        container.customPinboards.filter(\.isShared).count
    }

    private var lockedPinboardsCount: Int {
        container.customPinboards.filter { container.lockStateStore.isLocked($0.id) }.count
    }

    private var cardsCountLabel: String {
        if isLoadingCount {
            return "Loading"
        }

        guard let totalCardsCount else {
            return "-"
        }

        return "\(totalCardsCount)"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private func loadTotalCardsCount() async {
        isLoadingCount = true
        defer { isLoadingCount = false }

        do {
            let fetched = try await container.queryService.items(query: "", pinboardID: nil, limit: 5000)
            totalCardsCount = fetched.count
        } catch {
            totalCardsCount = nil
        }
    }
}
