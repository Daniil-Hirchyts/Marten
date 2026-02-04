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
    let lockedPinboardIDs: Set<UUID>
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
        Button {
            onPaste()
        } label: {
            Label("Paste", systemImage: "arrow.turn.up.left")
        }
        .accessibilityIdentifier("\(identifierPrefix).paste")

        Button {
            onPastePlainText()
        } label: {
            Label("Paste as Plain Text", systemImage: "textformat")
        }
        .accessibilityIdentifier("\(identifierPrefix).pastePlainText")

        Divider()

        if item.itemTypeValue == .url {
            Button {
                openLink()
            } label: {
                Label("Open Link", systemImage: "safari")
            }
            .accessibilityIdentifier("\(identifierPrefix).openLink")
        }

        if allowPinning {
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .accessibilityIdentifier("\(identifierPrefix).pin")
        }

        Button {
            onCopy()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("\(identifierPrefix).copy")

        Menu {
            ForEach(pinboards) { pinboard in
                let isAssigned = assignedPinboardIDs.contains(pinboard.id)
                let isLocked = lockedPinboardIDs.contains(pinboard.id)
                Button {
                    onMoveToPinboard(pinboard)
                } label: {
                    Label {
                        Text(pinboard.name)
                    } icon: {
                        Image(nsImage: NSImage.pinboardMenuIcon(
                            colorHex: pinboard.colorHex,
                            sign: pinboard.iconName,
                            size: 16,
                            isAssigned: isAssigned,
                            isLocked: isLocked
                        ))
                    }
                }
                .accessibilityIdentifier("\(identifierPrefix).move.\(pinboard.id.uuidString)")
            }
            Divider()
            Button {
                onCreatePinboard()
            } label: {
                Label("New Pinboard...", systemImage: "plus")
            }
            .accessibilityIdentifier("\(identifierPrefix).move.new")
        } label: {
            Label("Move to Pinboard", systemImage: "folder")
        }
        .accessibilityIdentifier("\(identifierPrefix).move")

        Divider()

        Button {
            onEdit()
        } label: {
            Label("Edit...", systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("\(identifierPrefix).edit")

        Button {
            onRename()
        } label: {
            Label("Rename...", systemImage: "character.cursor.ibeam")
        }
        .accessibilityIdentifier("\(identifierPrefix).rename")

        Button {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
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
    let onCustomize: () -> Void
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

            Button("Rename") {
                onRename()
            }
            .accessibilityIdentifier("\(identifierPrefix).rename")
            Button("Customize…") {
                onCustomize()
            }
            .accessibilityIdentifier("\(identifierPrefix).customize")
            Button("Delete") {
                onDelete()
            }
            .accessibilityIdentifier("\(identifierPrefix).delete")
        }
    }
}
