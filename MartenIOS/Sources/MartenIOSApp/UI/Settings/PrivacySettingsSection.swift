import SwiftUI

struct PrivacySettingsSection: View {
    @Bindable var container: MartenIOSAppContainer
    // Link previews setting is stored directly in UserDefaults to match LinkPreviewFetcher
    @AppStorage("generateLinkPreviews") private var generateLinkPreviews = false

    var body: some View {
        Section {
            SettingsRow(
                title: "Show during screen sharing",
                subtitle: "Allow Marten content to appear to others when you share your screen.",
                action: {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { container.showDuringScreenSharing },
                            set: { container.showDuringScreenSharing = $0 }
                        )
                    )
                    .labelsHidden()
                }
            )

            SettingsRow(
                title: "Generate link previews",
                subtitle: "Download web content for previews; may activate one-time or analytics-sensitive links.",
                action: {
                    Toggle("", isOn: $generateLinkPreviews)
                        .labelsHidden()
                }
            )
        } header: {
            Text("Privacy")
        }
    }
}
