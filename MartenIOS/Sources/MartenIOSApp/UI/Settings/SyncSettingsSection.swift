import MartenCore
import SwiftUI

struct SyncSettingsSection: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        MartenGlassSurface(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("iCloud Sync", systemImage: "icloud")
                    .font(.headline)

                if let syncCoordinator = container.syncCoordinator {
                    LiveSyncSettingsContent(
                        container: container,
                        syncCoordinator: syncCoordinator
                    )
                } else {
                    Text("iCloud sync is unavailable for this build configuration.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LiveSyncSettingsContent: View {
    @Bindable var container: MartenIOSAppContainer
    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Enable iCloud Sync",
                isOn: Binding(
                    get: { syncCoordinator.syncEnabled },
                    set: { enabled in
                        Task {
                            await container.setSyncEnabled(enabled)
                        }
                    }
                )
            )

            HStack {
                Text("Status")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .accessibilityLabel("Sync status: \(statusText)")
            }

            if let lastSyncDate = syncCoordinator.lastSyncDate {
                HStack {
                    Text("Last Sync")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                MartenGlassButton(action: {
                    Task {
                        await container.triggerSyncNow()
                    }
                }) {
                    HStack(spacing: 6) {
                        if container.isRunningSyncAction {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(container.isRunningSyncAction ? "Syncing" : "Sync Now")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .disabled(container.isRunningSyncAction || !syncCoordinator.syncEnabled)
                .accessibilityHint("Trigger an immediate iCloud sync")
            }
        }
    }

    private var statusText: String {
        switch syncCoordinator.status {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .error(let error):
            return error.localizedDescription
        }
    }

    private var statusColor: Color {
        switch syncCoordinator.status {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .error:
            return .red
        }
    }
}
