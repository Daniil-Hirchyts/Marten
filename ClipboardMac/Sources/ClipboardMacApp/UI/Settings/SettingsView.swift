import ClipboardCore
import SwiftUI

struct SettingsView: View {
    var syncCoordinator: SyncCoordinator?

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                        .accessibilityIdentifier("settings.tab.general")
                        .accessibilityLabel("General tab")
                }

            if let syncCoordinator {
                AccountTab(syncCoordinator: syncCoordinator)
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle")
                            .accessibilityIdentifier("settings.tab.account")
                            .accessibilityLabel("Account tab")
                    }
            } else {
                AccountUnavailableTab()
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle")
                            .accessibilityIdentifier("settings.tab.account")
                            .accessibilityLabel("Account tab")
                    }
            }

            PrivacyTab()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                        .accessibilityIdentifier("settings.tab.privacy")
                        .accessibilityLabel("Privacy tab")
                }

            ShortcutsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                        .accessibilityIdentifier("settings.tab.shortcuts")
                        .accessibilityLabel("Shortcuts tab")
                }
        }
        .frame(width: 600, height: 500)
    }
}

private struct AccountUnavailableTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud Sync Unavailable")
                .font(.headline)
            Text("This build is not signed with iCloud entitlements.")
                .foregroundStyle(.secondary)
            Text("Run the signed app bundle to enable iCloud sync.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
