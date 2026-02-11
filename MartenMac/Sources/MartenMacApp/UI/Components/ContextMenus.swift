import AppKit
import MartenCore
import Foundation
import SwiftUI

struct CardContextMenu: View {
    let item: ClipItem
    let itemID: UUID
    let isPinned: Bool
    let allowPinning: Bool
    let readOnly: Bool
    let assignedPinboardIDs: Set<UUID>
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onEdit: (ClipItem) -> Void
    let onRename: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var identifierPrefix: String {
        "overlay.itemMenu.\(itemID.uuidString)"
    }

    var body: some View {
        Button {
            onPaste(item)
        } label: {
            Label("Paste", systemImage: "arrow.turn.up.left")
        }
        .disabled(readOnly)
        .accessibilityIdentifier("\(identifierPrefix).paste")

        Button {
            onPastePlainText(item)
        } label: {
            Label("Paste as Plain Text", systemImage: "textformat")
        }
        .disabled(readOnly)
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
                onTogglePin(item)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .accessibilityIdentifier("\(identifierPrefix).pin")
        }

        Button {
            onCopy(item)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("\(identifierPrefix).copy")

        if !readOnly {
            Menu {
                ForEach(pinboards) { pinboard in
                    let isAssigned = assignedPinboardIDs.contains(pinboard.id)
                    let isLocked = lockedPinboardIDs.contains(pinboard.id)
                    Button {
                        onMoveToPinboard(item, pinboard)
                    } label: {
                        Label {
                            Text(pinboard.name)
                        } icon: {
                            Image(nsImage: NSImage.pinboardMenuIcon(
                                colorHex: pinboard.colorHex,
                                sign: pinboard.iconName,
                                size: 16,
                                isAssigned: isAssigned,
                                isLocked: isLocked,
                                colorScheme: colorScheme
                            ))
                        }
                    }
                    .accessibilityIdentifier("\(identifierPrefix).move.\(pinboard.id.uuidString)")
                }
                Divider()
                Button {
                    onCreatePinboard(item)
                } label: {
                    Label("New Pinboard...", systemImage: "plus")
                }
                .accessibilityIdentifier("\(identifierPrefix).move.new")
            } label: {
                Label("Move to Pinboard", systemImage: "circle.dashed")
            }
            .accessibilityIdentifier("\(identifierPrefix).move")
        }

        Divider()

        Button {
            onEdit(item)
        } label: {
            Label("Edit...", systemImage: "square.and.pencil")
        }
        .disabled(readOnly)
        .accessibilityIdentifier("\(identifierPrefix).edit")

        Button {
            onRename(item)
        } label: {
            Label("Rename...", systemImage: "character.cursor.ibeam")
        }
        .disabled(readOnly)
        .accessibilityIdentifier("\(identifierPrefix).rename")

        Button {
            onDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(readOnly)
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
    let isShared: Bool
    let isShareOwner: Bool
    let sharingEnabled: Bool
    let onSetLockEnabled: (Bool) -> Void
    let onUnlock: () -> Void
    let onLockNow: () -> Void
    let onRename: () -> Void
    let onCustomize: () -> Void
    let onDelete: () -> Void
    var onSharePinboard: (() -> Void)? = nil
    var onManageSharing: (() -> Void)? = nil
    var onStopSharing: (() -> Void)? = nil
    var onLeaveSharedPinboard: (() -> Void)? = nil

    private var identifierPrefix: String {
        "overlay.pinboardMenu.\(pinboardID.uuidString)"
    }

    var body: some View {
        if canEdit {
            // Sharing actions
            if sharingEnabled {
                if isShared {
                    if isShareOwner {
                        Menu {
                            Button {
                                onManageSharing?()
                            } label: {
                                Label("Manage Sharing…", systemImage: "person.2")
                            }
                            .accessibilityIdentifier("\(identifierPrefix).manageSharing")

                            Divider()

                            Button(role: .destructive) {
                                onStopSharing?()
                            } label: {
                                Label("Stop Sharing…", systemImage: "person.2.slash.fill")
                            }
                            .accessibilityIdentifier("\(identifierPrefix).stopSharing")
                        } label: {
                            Label("Sharing", systemImage: "person.2")
                        }
                        .accessibilityIdentifier("\(identifierPrefix).sharing")
                    } else {
                        Button {
                            onLeaveSharedPinboard?()
                        } label: {
                            Label("Leave Shared Pinboard", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .accessibilityIdentifier("\(identifierPrefix).leaveShare")
                    }
                    Divider()
                } else if !isLocked {
                    Button {
                        onSharePinboard?()
                    } label: {
                        Label("Share Pinboard…", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("\(identifierPrefix).share")
                    Divider()
                }
            }

            // Lock actions (hidden when shared)
            if !isShared {
                if isLocked {
                    if isUnlocked {
                        Button {
                            onLockNow()
                        } label: {
                            Label("Lock Now", systemImage: "lock.fill")
                        }
                        .accessibilityIdentifier("\(identifierPrefix).lockNow")
                        Button {
                            onSetLockEnabled(false)
                        } label: {
                            Label("Disable Lock", systemImage: "lock.open")
                        }
                        .accessibilityIdentifier("\(identifierPrefix).disableLock")
                    } else {
                        Button {
                            onUnlock()
                        } label: {
                            Label("Unlock", systemImage: "lock.open")
                        }
                        .accessibilityIdentifier("\(identifierPrefix).unlock")
                    }
                } else {
                    Button {
                        onSetLockEnabled(true)
                    } label: {
                        Label("Lock Pinboard", systemImage: "lock")
                    }
                    .accessibilityIdentifier("\(identifierPrefix).enableLock")
                }

                Divider()
            }

            if !isShared || isShareOwner {
                Button {
                    onRename()
                } label: {
                    Label("Rename", systemImage: "character.cursor.ibeam")
                }
                .accessibilityIdentifier("\(identifierPrefix).rename")
                Button {
                    onCustomize()
                } label: {
                    Label("Customize…", systemImage: "paintbrush")
                }
                .accessibilityIdentifier("\(identifierPrefix).customize")
                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("\(identifierPrefix).delete")
            }
        }
    }
}
