import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IntegrationsSettingsSection: View {
    @State private var statusModel = IntegrationsStatusModel()

    var body: some View {
        MartenGlassSurface(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Integrations", systemImage: "puzzlepiece.extension")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    statusRow(
                        title: "Share Extension",
                        isEnabled: statusModel.shareExtensionRecentlyUsed,
                        help: statusModel.shareExtensionRecentlyUsed
                            ? "Used recently"
                            : "Enable in the iOS Share Sheet"
                    )
                    statusRow(
                        title: "Keyboard Extension",
                        isEnabled: statusModel.keyboardLikelyEnabled,
                        help: statusModel.keyboardLikelyEnabled
                            ? "Activity detected recently"
                            : "Enable keyboard + Full Access in Settings"
                    )
                    statusRow(
                        title: "Widgets",
                        isEnabled: true,
                        help: "Add Marten widgets from Home or Lock Screen"
                    )
                    statusRow(
                        title: "Siri Shortcuts",
                        isEnabled: true,
                        help: "Open Shortcuts and add Marten actions"
                    )
                }

                #if canImport(UIKit)
                HStack {
                    Spacer()
                    MartenGlassButton(action: openSystemSettings) {
                        Label("Open iOS Settings", systemImage: "gearshape")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                #endif
            }
        }
        .task {
            statusModel.refresh()
        }
    }

    private func statusRow(title: String, isEnabled: Bool, help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(isEnabled ? "Ready" : "Not Enabled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEnabled ? .green : .secondary)
            }
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
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
