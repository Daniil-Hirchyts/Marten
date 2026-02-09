import MartenMacServices
import SwiftUI

struct MenuBarView: View {
    let onShowMarten: () -> Void

    @StateObject private var screenSharingManager = ScreenSharingManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Show Marten") {
                onShowMarten()
            }
            .accessibilityIdentifier("menubar.button.showMarten")
            .accessibilityLabel("Show Marten")

            Divider()

            Toggle("Screen Sharing Mode", isOn: $screenSharingManager.isScreenSharingModeActive)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .accessibilityIdentifier("menubar.toggle.screenSharingMode")
                .accessibilityLabel("Screen Sharing Mode")
        }
        .padding(12)
        .frame(width: 180)
    }
}
