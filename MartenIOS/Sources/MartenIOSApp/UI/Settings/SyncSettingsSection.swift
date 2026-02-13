import MartenCore
import SwiftUI

struct SyncSettingsSection: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        if let syncCoordinator = container.syncCoordinator {
            LiveSyncSettingsContent(
                container: container,
                syncCoordinator: syncCoordinator
            )
        } else {
            SettingsRow(
                title: "iCloud Unavailable",
                subtitle: "Sync is not available for this build"
            )
        }
    }
}

private struct LiveSyncSettingsContent: View {
    @Bindable var container: MartenIOSAppContainer
    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        SettingsRow(
            title: "Enable iCloud Sync",
            action: {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { syncCoordinator.syncEnabled },
                        set: { enabled in
                            Task { await container.setSyncEnabled(enabled) }
                        }
                    )
                )
                .labelsHidden()
            }
        )

        if syncCoordinator.syncEnabled {
            Button {
                Task { await container.triggerSyncNow() }
            } label: {
                SettingsRow(
                    title: container.isRunningSyncAction ? "Syncing..." : "Sync Now",
                    titleColor: .accentColor,
                    subtitle: syncSubtitle,
                    action: {
                        if container.isRunningSyncAction {
                            ProgressView()
                                .controlSize(.small)
                        } else if case .error = syncCoordinator.status {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                )
            }
            .disabled(container.isRunningSyncAction)
        }
    }

    private var syncSubtitle: String {
        let (statusTitle, _, _) = statusInfo
        var components: [String] = []
        
        // Don't show "Idle" as it's the default state and redundant with "Sync Now"
        if statusTitle != "Idle" {
            components.append(statusTitle)
        }
        
        if let lastSyncDate = syncCoordinator.lastSyncDate {
            components.append(lastSyncDate.formatted(date: .abbreviated, time: .shortened))
        }
        
        if components.isEmpty {
            return "Ready"
        }
        
        return components.joined(separator: " • ")
    }

    private var statusInfo: (String, Color, String) {
        switch syncCoordinator.status {
        case .idle:
            return ("Idle", .gray, "minus.circle")
        case .syncing:
            return ("Syncing", .blue, "arrow.triangle.2.circlepath")
        case .synced:
            return ("Synced", .green, "checkmark.circle.fill")
        case .error(let error):
            return ("Error", .red, "exclamationmark.triangle.fill")
        }
    }
}
