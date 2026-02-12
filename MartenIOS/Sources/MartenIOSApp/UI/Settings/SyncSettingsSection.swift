import MartenCore
import SwiftUI

struct SyncSettingsSection: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        Section {
            if let syncCoordinator = container.syncCoordinator {
                LiveSyncSettingsContent(
                    container: container,
                    syncCoordinator: syncCoordinator
                )
            } else {
                Label {
                    Text("iCloud sync is unavailable for this build.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Label("iCloud Sync", systemImage: "icloud")
        }
    }
}

private struct LiveSyncSettingsContent: View {
    @Bindable var container: MartenIOSAppContainer
    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        Toggle(
            "Enable iCloud Sync",
            isOn: Binding(
                get: { syncCoordinator.syncEnabled },
                set: { enabled in
                    Task { await container.setSyncEnabled(enabled) }
                }
            )
        )

        HStack {
            Text("Status")
            Spacer()
            statusBadge
        }

        if let lastSyncDate = syncCoordinator.lastSyncDate {
            HStack {
                Text("Last Sync")
                Spacer()
                Text(lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        Button {
            Task { await container.triggerSyncNow() }
        } label: {
            HStack {
                if container.isRunningSyncAction {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(container.isRunningSyncAction ? "Syncing…" : "Sync Now")
            }
        }
        .disabled(container.isRunningSyncAction || !syncCoordinator.syncEnabled)
        .accessibilityHint("Trigger an immediate iCloud sync")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch syncCoordinator.status {
        case .idle:
            StatusBadge(title: "Idle", systemImage: "minus.circle", tint: .secondary)
        case .syncing:
            StatusBadge(title: "Syncing", systemImage: "arrow.triangle.2.circlepath", tint: .blue)
        case .synced:
            StatusBadge(title: "Synced", systemImage: "checkmark.circle.fill", tint: .green)
        case .error(let error):
            StatusBadge(
                title: error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
            )
        }
    }
}
