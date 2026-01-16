import ClipboardMacServices
import SwiftUI

struct MenuBarView: View {
    let onToggle: () -> Void
    let onNewItem: () -> Void

    @StateObject private var screenSharingManager = ScreenSharingManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Toggle Overlay") {
                onToggle()
            }
            .accessibilityIdentifier("menubar.button.toggleOverlay")
            .accessibilityLabel("Toggle Overlay")
            Button("New Text Item") {
                onNewItem()
            }
            .accessibilityIdentifier("menubar.button.newTextItem")
            .accessibilityLabel("New Text Item")

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
