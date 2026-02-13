import SwiftUI

struct IntegrationsSettingsSection: View {
    @State private var statusModel = IntegrationsStatusModel()

    var body: some View {
        Section {
            NavigationLink {
                KeyboardIntegrationView()
            } label: {
                SettingsRow(
                    icon: "keyboard",
                    iconColor: .blue,
                    title: "Keyboard",
                    value: statusModel.keyboardLikelyEnabled ? "On" : "Off"
                )
            }

            NavigationLink {
                ShareExtensionIntegrationView()
            } label: {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    iconColor: .green,
                    title: "Action Extension",
                    value: statusModel.shareExtensionRecentlyUsed ? "Active" : nil
                )
            }

            NavigationLink {
                WidgetsIntegrationView()
            } label: {
                SettingsRow(
                    icon: "square.split.2x2", // Changed icon to match iOS Settings style for HomeScreen
                    iconColor: .orange,
                    title: "Widget"
                )
            }

            NavigationLink {
                SiriIntegrationView()
            } label: {
                SettingsRow(
                    icon: "waveform", // Changed icon to match iOS Settings style for Siri
                    iconColor: .purple,
                    title: "Siri & Shortcuts"
                )
            }
        } header: {
            Text("Integrations")
        }
        .task {
            statusModel.refresh()
        }
    }
}
