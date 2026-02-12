import SwiftUI

struct MartenIOSSettingsView: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        Form {
            SyncSettingsSection(container: container)
            AppearanceSettingsSection(container: container)
            IntegrationsSettingsSection()
            SubscriptionSection()

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Marten")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
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

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
