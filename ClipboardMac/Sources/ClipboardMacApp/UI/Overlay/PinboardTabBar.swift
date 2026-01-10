import ClipboardCore
import SwiftUI

struct PinboardTabBar: View {
    let pinboards: [Pinboard]
    let selectedID: UUID?
    let onSelect: (UUID?) -> Void
    let onCreate: () -> Void
    let onRename: (Pinboard) -> Void
    let onDelete: (Pinboard) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PinboardTab(title: "All", isSelected: selectedID == nil) {
                    onSelect(nil)
                }

                ForEach(pinboards) { pinboard in
                    PinboardTab(title: pinboard.name, isSelected: selectedID == pinboard.id) {
                        onSelect(pinboard.id)
                    }
                    .contextMenu {
                        PinboardContextMenu(
                            canEdit: !pinboard.isSystemClipboard,
                            onRename: { onRename(pinboard) },
                            onDelete: { onDelete(pinboard) }
                        )
                    }
                }

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
