import ClipboardCore
import Foundation
import SwiftUI

struct CardContextMenu: View {
    let itemID: UUID
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

    private var identifierPrefix: String {
        "overlay.itemMenu.\(itemID.uuidString)"
    }

    var body: some View {
        Button("Paste") {
            onPaste()
        }
        .accessibilityIdentifier("\(identifierPrefix).paste")
        Button("Paste as Plain Text") {
            onPastePlainText()
        }
        .accessibilityIdentifier("\(identifierPrefix).pastePlainText")
        Divider()
        if allowPinning {
            Button(isPinned ? "Unpin" : "Pin") {
                onTogglePin()
            }
            .accessibilityIdentifier("\(identifierPrefix).pin")
        }
        Button("Copy") {
            onCopy()
        }
        .accessibilityIdentifier("\(identifierPrefix).copy")
        Menu("Move to Pinboard") {
            ForEach(pinboards) { pinboard in
                Button(pinboard.name) {
                    onMoveToPinboard(pinboard)
                }
                .accessibilityIdentifier("\(identifierPrefix).move.\(pinboard.id.uuidString)")
            }
            Divider()
            Button("New Pinboard...") {
                onCreatePinboard()
            }
            .accessibilityIdentifier("\(identifierPrefix).move.new")
        }
        .accessibilityIdentifier("\(identifierPrefix).move")
        Divider()
        Button("Rename...") {
            onRename()
        }
        .accessibilityIdentifier("\(identifierPrefix).rename")
        Button("Delete") {
            onDelete()
        }
        .accessibilityIdentifier("\(identifierPrefix).delete")
    }
}

struct PinboardContextMenu: View {
    let canEdit: Bool
    let pinboardID: UUID
    let onRename: () -> Void
    let onColorChange: (String) -> Void
    let onDelete: () -> Void

    private var identifierPrefix: String {
        "overlay.pinboardMenu.\(pinboardID.uuidString)"
    }

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
                    .accessibilityIdentifier("\(identifierPrefix).color.\(color.hex)")
                }
            }
            .accessibilityIdentifier("\(identifierPrefix).color")
            Button("Rename") {
                onRename()
            }
            .accessibilityIdentifier("\(identifierPrefix).rename")
            Button("Delete") {
                onDelete()
            }
            .accessibilityIdentifier("\(identifierPrefix).delete")
        }
    }
}
