import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                        .accessibilityIdentifier("settings.tab.general")
                        .accessibilityLabel("General tab")
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
