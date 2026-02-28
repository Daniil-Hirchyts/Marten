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
    }
}
