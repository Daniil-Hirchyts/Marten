import ClipboardCore
import SwiftUI

struct CardContextMenu: View {
    let isPinned: Bool
    let pinboards: [Pinboard]
    let onTogglePin: () -> Void
    let onCopy: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(isPinned ? "Unpin" : "Pin") {
            onTogglePin()
        }
        Button("Copy") {
            onCopy()
        }
        Menu("Move to Pinboard") {
            ForEach(pinboards) { pinboard in
                Button(pinboard.name) {
                    onMoveToPinboard(pinboard)
                }
            }
            Divider()
            Button("New Pinboard...") {
                onCreatePinboard()
            }
        }
        Divider()
        Button("Delete") {
            onDelete()
        }
    }
}

struct PinboardContextMenu: View {
    let canEdit: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if canEdit {
            Button("Rename") {
                onRename()
            }
            Button("Delete") {
                onDelete()
            }
        }
    }
}
