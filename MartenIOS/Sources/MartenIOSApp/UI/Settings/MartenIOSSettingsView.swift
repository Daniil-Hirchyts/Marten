import SwiftUI

struct MartenIOSSettingsView: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        List {
            IntegrationsSettingsSection()

            PrivacySettingsSection(container: container)

            Section {
                SubscriptionSection()
                SyncSettingsSection(container: container)
                AppearanceSettingsSection(container: container)
            } header: {
                Text("General")
            }

            DataCleanupSettingsSection(container: container)

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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
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
