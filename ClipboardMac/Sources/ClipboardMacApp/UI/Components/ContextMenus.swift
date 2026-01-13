import ClipboardCore
import SwiftUI

struct CardContextMenu: View {
    let isPinned: Bool
    let allowPinning: Bool
    let pinboards: [Pinboard]
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onTogglePin: () -> Void
    let onCopy: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Paste") {
            onPaste()
        }
        Button("Paste as Plain Text") {
            onPastePlainText()
        }
        Divider()
        if allowPinning {
            Button(isPinned ? "Unpin" : "Pin") {
                onTogglePin()
            }
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
        Button("Rename...") {
            onRename()
        }
        Button("Delete") {
            onDelete()
        }
    }
}

struct PinboardContextMenu: View {
    let canEdit: Bool
    let onRename: () -> Void
    let onColorChange: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        if canEdit {
            Menu("Color") {
                ForEach(PinboardPalette.all, id: \.hex) { color in
                    Button {
                        onColorChange(color.hex)
                    } label: {
                        HStack {
                            Image(nsImage: .colorCircle(hex: color.hex))
                            Text(color.name)
                        }
                    }
                }
            }
            Button("Rename") {
                onRename()
            }
            Button("Delete") {
                onDelete()
            }
        }
    }
}
