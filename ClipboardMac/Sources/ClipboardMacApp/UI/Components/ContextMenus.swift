import AppKit
import ClipboardCore
import Foundation
import SwiftUI

struct CardContextMenu: View {
    let item: ClipItem
    let itemID: UUID
    let isPinned: Bool
    let allowPinning: Bool
    let assignedPinboardIDs: Set<UUID>
    let pinboards: [Pinboard]
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onTogglePin: () -> Void
    let onCopy: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onEdit: () -> Void
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
        if item.itemTypeValue == .url {
            Button("Open Link") {
                openLink()
            }
            .accessibilityIdentifier("\(identifierPrefix).openLink")
        }
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
                let isAssigned = assignedPinboardIDs.contains(pinboard.id)
                Button {
                    onMoveToPinboard(pinboard)
                } label: {
                    if isAssigned {
                        Label(pinboard.name, systemImage: "checkmark")
                    } else {
                        Text(pinboard.name)
                    }
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
        Button("Edit...") {
            onEdit()
        }
        .accessibilityIdentifier("\(identifierPrefix).edit")
        Button("Rename...") {
            onRename()
        }
        .accessibilityIdentifier("\(identifierPrefix).rename")
        Button("Delete") {
            onDelete()
        }
        .accessibilityIdentifier("\(identifierPrefix).delete")
    }
    
    private func openLink() {
        guard item.itemTypeValue == .url,
              let urlString = item.primaryText,
              !urlString.isEmpty else {
            return
        }
        
        // Handle URLs with or without scheme
        let normalizedURLString: String
        if urlString.lowercased().hasPrefix("http://") || urlString.lowercased().hasPrefix("https://") {
            normalizedURLString = urlString
        } else {
            normalizedURLString = "https://\(urlString)"
        }
        
        if let url = URL(string: normalizedURLString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PinboardContextMenu: View {
    let canEdit: Bool
    let pinboardID: UUID
    let isLocked: Bool
    let isUnlocked: Bool
    let onSetLockEnabled: (Bool) -> Void
    let onUnlock: () -> Void
    let onLockNow: () -> Void
    let onRename: () -> Void
    let onColorChange: (String) -> Void
    let onDelete: () -> Void

    private var identifierPrefix: String {
        "overlay.pinboardMenu.\(pinboardID.uuidString)"
    }

    var body: some View {
        if canEdit {
            if isLocked {
                if isUnlocked {
                    Button("Lock Now") {
                        onLockNow()
                    }
                    .accessibilityIdentifier("\(identifierPrefix).lockNow")
                    Button("Disable Lock") {
                        onSetLockEnabled(false)
                    }
                    .accessibilityIdentifier("\(identifierPrefix).disableLock")
                } else {
                    Button("Unlock") {
                        onUnlock()
                    }
                    .accessibilityIdentifier("\(identifierPrefix).unlock")
                }
            } else {
                Button("Lock Pinboard") {
                    onSetLockEnabled(true)
                }
                .accessibilityIdentifier("\(identifierPrefix).enableLock")
            }

            Divider()

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
