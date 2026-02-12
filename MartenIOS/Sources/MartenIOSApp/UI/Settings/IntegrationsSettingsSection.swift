import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IntegrationsSettingsSection: View {
    @State private var statusModel = IntegrationsStatusModel()

    var body: some View {
        Section {
            integrationRow(
                title: "Share Extension",
                icon: "square.and.arrow.up",
                isEnabled: statusModel.shareExtensionRecentlyUsed,
                help: statusModel.shareExtensionRecentlyUsed
                    ? "Used recently"
                    : "Enable in the iOS Share Sheet"
            )

            integrationRow(
                title: "Keyboard",
                icon: "keyboard",
                isEnabled: statusModel.keyboardLikelyEnabled,
                help: statusModel.keyboardLikelyEnabled
                    ? "Activity detected"
                    : "Enable keyboard + Full Access in Settings"
            )

            integrationRow(
                title: "Widgets",
                icon: "widget.small",
                isEnabled: true,
                help: "Add from Home or Lock Screen"
            )

            integrationRow(
                title: "Siri Shortcuts",
                icon: "sparkles",
                isEnabled: true,
                help: "Available in the Shortcuts app"
            )

            #if canImport(UIKit)
            Button {
                openSystemSettings()
            } label: {
                Label("Open iOS Settings", systemImage: "gearshape")
            }
            #endif
        } header: {
            Label("Integrations", systemImage: "puzzlepiece.extension")
        }
        .task {
            statusModel.refresh()
        }
    }

    private func integrationRow(
        title: String,
        icon: String,
        isEnabled: Bool,
        help: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(isEnabled ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isEnabled ? "Ready" : "Not Enabled"), \(help)")
    }

    #if canImport(UIKit)
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #endif
}
