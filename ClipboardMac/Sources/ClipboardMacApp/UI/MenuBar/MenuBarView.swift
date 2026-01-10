import SwiftUI

struct MenuBarView: View {
    let onToggle: () -> Void
    let onNewItem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Toggle Overlay") {
                onToggle()
            }
            Button("New Text Item") {
                onNewItem()
            }
        }
        .padding(12)
        .frame(width: 180)
    }
}
