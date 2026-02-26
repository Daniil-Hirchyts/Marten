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
    let onConvertType: (ClipItem, ItemType) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onEdit: (ClipItem) -> Void
    let onRename: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var identifierPrefix: String {
        "overlay.itemMenu.\(itemID.uuidString)"
    }

    private static let convertibleTypes: [ItemType] = [
        .text,
        .url,
        .code,
        .color,
    ]

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

        let conversionTargets = Self.conversionTargets(
            for: item.itemTypeValue,
            sourceText: item.plainTextContent ?? item.primaryText
        )
        if !readOnly, !conversionTargets.isEmpty {
            Menu {
                ForEach(conversionTargets, id: \.self) { type in
                    Button {
                        onConvertType(item, type)
                    } label: {
                        Label(Self.conversionLabel(for: type), systemImage: Self.conversionIcon(for: type))
                    }
                }
            } label: {
                Label("Convert Type", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityIdentifier("\(identifierPrefix).convertType")
        }

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

    private static func conversionTargets(for currentType: ItemType, sourceText: String?) -> [ItemType] {
        guard convertibleTypes.contains(currentType) else { return [] }

        let normalizedText = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return convertibleTypes.compactMap { candidate in
            guard candidate != currentType else { return nil }

            if candidate == .url, !hasConvertibleURL(in: normalizedText) {
                return nil
            }

            if candidate == .color, !hasConvertibleColor(in: normalizedText) {
                return nil
            }

            return candidate
        }
    }

    private static func conversionLabel(for type: ItemType) -> String {
        switch type {
        case .text, .richText:
            return "Text"
        case .url:
            return "Link"
        case .code:
            return "Code"
        case .color:
            return "Color"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .mixed:
            return "Mixed"
        }
    }

    private static func conversionIcon(for type: ItemType) -> String {
        switch type {
        case .text, .richText:
            return "doc.plaintext"
        case .url:
            return "link"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .color:
            return "paintpalette"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .mixed:
            return "square.stack.3d.up"
        }
    }

    private static func hasConvertibleColor(in text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return normalizedHexColor(from: text) != nil
    }

    private static func normalizedHexColor(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if candidate.lowercased().hasPrefix("0x") {
            candidate = String(candidate.dropFirst(2))
        }
        if candidate.hasPrefix("#") {
            candidate = String(candidate.dropFirst())
        }

        let cleaned = candidate.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        guard cleaned.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            return nil
        }

        if cleaned.count == 3 {
            let chars = Array(cleaned)
            return
                "#\(String(repeating: String(chars[0]), count: 2))\(String(repeating: String(chars[1]), count: 2))\(String(repeating: String(chars[2]), count: 2))"
                .uppercased()
        }

        if cleaned.count == 6 {
            return "#\(cleaned)".uppercased()
        }

        if cleaned.count == 8 {
            let start = cleaned.startIndex
            let end = cleaned.index(start, offsetBy: 6)
            return "#\(String(cleaned[start..<end]))".uppercased()
        }

        return nil
    }

    private static func hasConvertibleURL(in text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if linkDetector?.firstMatch(in: text, options: [], range: fullRange) != nil {
            return true
        }

        guard !text.contains(where: \.isWhitespace) else { return false }

        if let directURL = URL(string: text),
            directURL.scheme != nil,
            directURL.host != nil
        {
            return true
        }

        guard text.contains(".") || text.lowercased().hasPrefix("localhost") else {
            return false
        }

        let prefixedText = "https://\(text)"
        guard let normalizedURL = URL(string: prefixedText), normalizedURL.host != nil else {
            return false
        }

        return true
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
