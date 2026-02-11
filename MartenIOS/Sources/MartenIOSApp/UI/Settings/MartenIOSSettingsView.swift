import SwiftUI

struct MartenIOSSettingsView: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SyncSettingsSection(container: container)
                AppearanceSettingsSection(container: container)
                IntegrationsSettingsSection()
                SubscriptionSection()
            }
            .padding(16)
        }
        .navigationTitle("Settings")
        .alert(
            "Sync Error",
            isPresented: Binding(
                get: { container.syncErrorMessage != nil },
                set: { _ in container.clearSyncError() }
            )
        ) {
            Button("OK") {
                container.clearSyncError()
            }
        } message: {
            Text(container.syncErrorMessage ?? "Unknown sync error")
        }
    }
}
