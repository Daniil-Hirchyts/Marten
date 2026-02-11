import AppKit
import MartenCore
import MartenMacServices
import CoreData
import SwiftUI

struct PinboardTabBarSection<CreatePopoverContent: View>: View {
    let pinboards: [Pinboard]
    let selectedID: UUID?
    let isLocked: (Pinboard) -> Bool
    let isUnlocked: (Pinboard) -> Bool
    @Binding var editingID: NSManagedObjectID?
    @Binding var isCreatePopoverPresented: Bool
    @ViewBuilder let createPopoverContent: () -> CreatePopoverContent
    
    // Restored Properties
    @Binding var draftName: String
    @Binding var draftColor: String
    @Binding var draftIcon: String?
    let isGlobalDragActive: Bool
    var itemDragPinboardDropTargetID: NSManagedObjectID? = nil
    let window: NSWindow?

    let onPreviewUpdate: (PinboardDragPreviewData?) -> Void
    let onSelect: (UUID?) -> Void
    let onCreate: () -> Void
    let onSetLockEnabled: (Pinboard, Bool) -> Void
    let onUnlock: (Pinboard) -> Void
    let onLockNow: (Pinboard) -> Void
    let onRename: (Pinboard) -> Void
    let onColorChange: (Pinboard, String) -> Void
    let onIconChange: (Pinboard, String?) -> Void
    let onDelete: (Pinboard) -> Void
    let onReorder: (Pinboard, Pinboard, Bool) -> Void
    let onReorderEnd: () -> Void
    let onMoveItem: (Pinboard, String) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    var onSharePinboard: ((Pinboard) -> Void)? = nil
    var onManageSharing: ((Pinboard) -> Void)? = nil
    var onStopSharing: ((Pinboard) -> Void)? = nil
    var onLeaveSharedPinboard: ((Pinboard) -> Void)? = nil
    @Binding var shareSheetPinboard: Pinboard?
    var sharingRepository: (any PinboardSharingRepositoryProtocol)?

    let coordinateSpaceName: String
    let horizontalPadding: CGFloat
    let rowHeight: CGFloat
    let onPinboardLayoutChange: (PinboardLayoutInfo) -> Void
    let onSearchFieldFrameChange: (CGRect?) -> Void

    var body: some View {
        PinboardTabBar(
            pinboards: pinboards,
            selectedID: selectedID,
            isLocked: isLocked,
            isUnlocked: isUnlocked,
            editingID: $editingID,
            isCreatePopoverPresented: $isCreatePopoverPresented,
            createPopoverContent: createPopoverContent,
            draftName: $draftName,
            draftColor: $draftColor,
            draftIcon: $draftIcon,
            isGlobalDragActive: isGlobalDragActive,
            itemDragPinboardDropTargetID: itemDragPinboardDropTargetID,
            window: window,
            onPreviewUpdate: onPreviewUpdate,
            onSelect: onSelect,
            onCreate: onCreate,
            onSetLockEnabled: onSetLockEnabled,
            onUnlock: onUnlock,
            onLockNow: onLockNow,
            onRename: onRename,
            onColorChange: onColorChange,
            onIconChange: onIconChange,
            onDelete: onDelete,
            onReorder: onReorder,
            onReorderEnd: onReorderEnd,
            onMoveItem: onMoveItem,
            onCommit: onCommit,
            onCancel: onCancel,
            onSharePinboard: onSharePinboard,
            onManageSharing: onManageSharing,
            onStopSharing: onStopSharing,
            onLeaveSharedPinboard: onLeaveSharedPinboard,
            shareSheetPinboard: $shareSheetPinboard,
            sharingRepository: sharingRepository,
            coordinateSpaceName: coordinateSpaceName
        )
        .padding(.horizontal, horizontalPadding)
        .frame(height: rowHeight, alignment: .center)
        .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
            onPinboardLayoutChange(layout)
        }
        .onPreferenceChange(SearchFieldFrameKey.self) { frame in
            onSearchFieldFrameChange(frame)
        }
    }
}
