import ClipboardCore
import SwiftUI

extension PinboardTabBar {
    @ViewBuilder
    func pinboardsContent(isMeasuring: Bool) -> some View {
        HStack(spacing: tabSpacing) {
            PinboardTab(
                title: "All", iconName: "tray", colorHex: nil, isSelected: selectedID == nil,
                minWidth: minTabWidth, maxWidth: maxTabWidth
            ) {
                onSelect(nil)
            }
            .id("all")
            .accessibilityIdentifier("overlay.pinboard.all")
            .accessibilityLabel("All items")
            .accessibilityValue(selectedID == nil ? "Selected" : "Not selected")
            .accessibilityHint(
                pinboardHint(title: "All items", isAll: true, isLocked: false, isUnlocked: false)
            )
            .accessibilityElement(children: .ignore)
            .background(
                GeometryReader { proxy in
                    if !isMeasuring {
                        let overlayFrame = overlayFrame(from: proxy)
                        let minX = proxy.frame(in: .named(scrollSpaceName)).minX
                        let barLocalFrame = localFrame(from: proxy)

                        Color.clear.preference(
                            key: PinboardLayoutInfoKey.self,
                            value: PinboardLayoutInfo(
                                tabFrames: [Self.allTabObjectID: barLocalFrame],
                                allOverlayFrame: overlayFrame,
                                scrollOffset: minX
                            )
                        )
                    }
                }
            )

            ForEach(Array(pinboards.enumerated()), id: \.element.objectID) { index, pinboard in
                if editingID == pinboard.objectID {
                    editorView(pinboard: pinboard)
                } else {
                    pinboardView(pinboard: pinboard, index: index + 1, isMeasuring: isMeasuring)
                }
            }
        }
    }

    @ViewBuilder
    func pinboardView(pinboard: Pinboard, index: Int, isMeasuring: Bool = false) -> some View {
        let isDragging = dragState?.itemID == pinboard.objectID
        let locked = isLocked(pinboard)
        let unlocked = isUnlocked(pinboard)

        let base = PinboardTab(
            title: pinboard.name,
            iconName: pinboard.iconName,
            colorHex: pinboard.colorHex,
            trailingIconName: locked ? (unlocked ? "lock.open.fill" : "lock.fill") : nil,
            isSelected: selectedID == pinboard.id, maxWidth: maxTabWidth
        ) {
            onSelect(pinboard.id)
        }
        .id(pinboard.id)
        .accessibilityIdentifier("overlay.pinboard.\(pinboard.id.uuidString)")
        .accessibilityLabel(pinboard.name)
        .accessibilityValue(selectedID == pinboard.id ? "Selected" : "Not selected")
        .accessibilityHint(
            pinboardHint(title: pinboard.name, isAll: false, isLocked: locked, isUnlocked: unlocked)
        )
        .accessibilityElement(children: .ignore)
        .opacity(isDragging ? 0.25 : 1)
        .background(
            GeometryReader { proxy in
                if !isMeasuring {
                    let overlayFrame = overlayFrame(from: proxy)
                    let localFrame = localFrame(from: proxy)

                    Color.clear.preference(
                        key: PinboardLayoutInfoKey.self,
                        value: PinboardLayoutInfo(
                            tabFrames: [pinboard.objectID: localFrame],
                            overlayPinboardFrames: [pinboard.objectID: overlayFrame]
                        )
                    )
                }
            }
        )
        .contextMenu {
            PinboardContextMenu(
                canEdit: !pinboard.isSystemClipboard,
                pinboardID: pinboard.id,
                isLocked: locked,
                isUnlocked: unlocked,
                onSetLockEnabled: { enabled in onSetLockEnabled(pinboard, enabled) },
                onUnlock: { onUnlock(pinboard) },
                onLockNow: { onLockNow(pinboard) },
                onRename: {
                    isStyleOnlyEditMode = false
                    pinnedEditorObjectID = pinboard.objectID
                    pinnedEditorWidth = frameManager.latestTabFrames[pinboard.objectID]?.width
                    onRename(pinboard)
                },
                onCustomize: {
                    isStyleOnlyEditMode = true
                    shouldPresentStylePickerFromMenu = true
                    pinnedEditorObjectID = pinboard.objectID
                    pinnedEditorWidth = frameManager.latestTabFrames[pinboard.objectID]?.width
                    DispatchQueue.main.async {
                        onRename(pinboard)
                    }
                },
                onDelete: { onDelete(pinboard) }
            )
        }

        if canReorder {
            base.simultaneousGesture(dragGesture(for: pinboard, index: index))
        } else {
            base
        }
    }

    func pinboardHint(title: String, isAll: Bool, isLocked: Bool, isUnlocked: Bool) -> String {
        var parts: [String] = []
        parts.append(isAll ? "Shows all items" : "Shows items in \(title)")
        if !isAll && isLocked {
            parts.append(isUnlocked ? "Temporarily unlocked" : "Locked")
        }
        if !isAll && canReorder {
            parts.append("Drag to reorder pinboards")
        }
        return parts.joined(separator: ". ")
    }
}
