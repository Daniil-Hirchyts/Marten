import AppKit
import SwiftUI

@available(macOS 14.0, *)
struct OverlaySettingsButton14<Label: View>: View {
    let closeOverlay: (@escaping () -> Void) -> Void
    let label: () -> Label

    @Environment(\.openWindow) private var openWindow

    init(
        closeOverlay: @escaping (@escaping () -> Void) -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.closeOverlay = closeOverlay
        self.label = label
    }

    var body: some View {
        Button {
            closeOverlay {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
                // openWindow shows the window but does not make it key; bring it
                // to front on the next tick after SwiftUI finishes creating it.
                DispatchQueue.main.async {
                    if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                        w.makeKeyAndOrderFront(nil)
                    }
                }
            }
        } label: { label() }
    }
}
