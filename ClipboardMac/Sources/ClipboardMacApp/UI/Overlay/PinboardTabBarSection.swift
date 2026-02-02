import AppKit
import ClipboardCore
import ClipboardMacServices
import CoreData
import SwiftUI

struct PinboardTabBarSection: View {
    let pinboards: [Pinboard]
    let selectedID: UUID?
    let isLocked: (Pinboard) -> Bool
    let isUnlocked: (Pinboard) -> Bool
    @Binding var editingID: NSManagedObjectID?
    @Binding var isCreating: Bool
    @Binding var draftName: String
    @Binding var draftColor: String
    let isGlobalDragActive: Bool
    let window: NSWindow?

    let onPreviewUpdate: (PinboardDragPreviewData?) -> Void
    let onSelect: (UUID?) -> Void
    let onCreate: () -> Void
    let onSetLockEnabled: (Pinboard, Bool) -> Void
    let onUnlock: (Pinboard) -> Void
    let onLockNow: (Pinboard) -> Void
    let onRename: (Pinboard) -> Void
    let onColorChange: (Pinboard, String) -> Void
    let onDelete: (Pinboard) -> Void
    let onReorder: (Pinboard, Pinboard, Bool) -> Void
    let onReorderEnd: () -> Void
    let onMoveItem: (Pinboard, String) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    let coordinateSpaceName: String
    let headerSideWidth: CGFloat
    let headerButtonSize: CGFloat
    let onPinboardLayoutChange: (PinboardLayoutInfo) -> Void
    let onSearchFieldFrameChange: (CGRect?) -> Void

    var body: some View {
        PinboardTabBar(
            pinboards: pinboards,
            selectedID: selectedID,
            isLocked: isLocked,
            isUnlocked: isUnlocked,
            editingID: $editingID,
            isCreating: $isCreating,
            draftName: $draftName,
            draftColor: $draftColor,
            isGlobalDragActive: isGlobalDragActive,
            window: window,
            onPreviewUpdate: onPreviewUpdate,
            onSelect: onSelect,
            onCreate: onCreate,
            onSetLockEnabled: onSetLockEnabled,
            onUnlock: onUnlock,
            onLockNow: onLockNow,
            onRename: onRename,
            onColorChange: onColorChange,
            onDelete: onDelete,
            onReorder: onReorder,
            onReorderEnd: onReorderEnd,
            onMoveItem: onMoveItem,
            onCommit: onCommit,
            onCancel: onCancel,
            coordinateSpaceName: coordinateSpaceName
        )
        .padding(.horizontal, headerSideWidth)
        .frame(height: headerButtonSize, alignment: .center)
        .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
            onPinboardLayoutChange(layout)
        }
        .onPreferenceChange(SearchFieldFrameKey.self) { frame in
            onSearchFieldFrameChange(frame)
        }
    }
}
