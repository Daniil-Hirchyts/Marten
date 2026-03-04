import AppKit
import MartenCore
import MartenMacServices
import CoreData
import SwiftUI

struct ItemGridActionHandlers {
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onConvertType: (ClipItem, ItemType) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onEdit: (ClipItem) -> Void
    let onRename: (ClipItem) -> Void
    let onCommitRename: (ClipItem, String) -> Void
    let onTap: (ClipItem) -> Void
    let onDoubleTap: (ClipItem) -> Void
    let onReorder: ([NSManagedObjectID], ClipItem, Bool) -> Void
    let onReorderEnd: () -> Void
    let onDropToPinboard: (ClipItem, NSManagedObjectID) -> Void
    let onDropToAll: (ClipItem) -> Void
    let onPasteOutside: ([NSManagedObjectID]) -> Void
    var onBeginNativeDrag: (([NSManagedObjectID]) -> Bool)? = nil
    var isNativeDragActive: (() -> Bool)? = nil
    var onPinboardDropTargetChanged: ((NSManagedObjectID?) -> Void)? = nil
}

struct ItemGridSection: View {
    let layoutAxis: OverlayLayoutAxis
    let isSelectedPinboardAwaitingUnlock: Bool
    let lockedPinboardTitle: String
    let canUnlockLockedPinboard: Bool
    let isAuthenticatingLock: Bool
    let onUnlockLockedPinboard: () -> Void

    let filteredItems: [ClipItem]
    let isSearchActive: Bool
    let selectedPinboardID: UUID?

    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let mode: OverlayMode
    let selectedItemIDs: Set<NSManagedObjectID>
    let editingItemID: NSManagedObjectID?
    let allowPinning: Bool
    let readOnly: Bool
    let clipItemEditor: any ClipItemEditing
    let isDragEnabled: Bool
    let isReorderingEnabled: Bool

    let actions: ItemGridActionHandlers

    let coordinateSpaceName: String
    let pinboardFrames: [NSManagedObjectID: CGRect]
    let allPinboardFrame: CGRect?
    let window: NSWindow?
    @Binding var dragPreviewData: DragPreviewData?
    let onPreviewUpdate: (DragPreviewData?) -> Void
    @Binding var previewItemID: NSManagedObjectID?
    @Binding var isPreviewPopoverPresented: Bool

    let pinboardSelectionKey: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isSelectedPinboardAwaitingUnlock {
                LockedPinboardOverlayView(
                    title: lockedPinboardTitle,
                    canUnlock: canUnlockLockedPinboard,
                    isAuthenticating: isAuthenticatingLock,
                    onUnlock: onUnlockLockedPinboard
                )
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if filteredItems.isEmpty {
                OverlayEmptyStateView(
                    isSearchActive: isSearchActive,
                    selectedPinboardID: selectedPinboardID
                )
                .padding(.horizontal, 14)
                .transition(.opacity)
            } else {
                Group {
                    if layoutAxis == .horizontal {
                        // .vertical and .compact both use ItemCompactColumn (handled by else)
                        ItemCardRow(
                            items: filteredItems,
                            pinboardSelectionKey: pinboardSelectionKey,
                            pinboards: pinboards,
                            lockedPinboardIDs: lockedPinboardIDs,
                            selectedPinboardID: selectedPinboardID,
                            mode: mode,
                            selectedItemIDs: selectedItemIDs,
                            editingItemID: editingItemID,
                            allowPinning: allowPinning,
                            readOnly: readOnly,
                            clipItemEditor: clipItemEditor,
                            isDragEnabled: isDragEnabled,
                            isReorderingEnabled: isReorderingEnabled,
                            onPaste: actions.onPaste,
                            onPastePlainText: actions.onPastePlainText,
                            onCopy: actions.onCopy,
                            onDelete: actions.onDelete,
                            onTogglePin: actions.onTogglePin,
                            onConvertType: actions.onConvertType,
                            onMoveToPinboard: actions.onMoveToPinboard,
                            onCreatePinboard: actions.onCreatePinboard,
                            onEdit: actions.onEdit,
                            onRename: actions.onRename,
                            onCommitRename: actions.onCommitRename,
                            onTap: actions.onTap,
                            onDoubleTap: actions.onDoubleTap,
                            onReorder: actions.onReorder,
                            onReorderEnd: actions.onReorderEnd,
                            onDropToPinboard: actions.onDropToPinboard,
                            onDropToAll: actions.onDropToAll,
                            onPasteOutside: actions.onPasteOutside,
                            onBeginNativeDrag: actions.onBeginNativeDrag,
                            isNativeDragActive: actions.isNativeDragActive,
                            onPinboardDropTargetChanged: actions.onPinboardDropTargetChanged,
                            coordinateSpaceName: coordinateSpaceName,
                            pinboardFrames: pinboardFrames,
                            allPinboardFrame: allPinboardFrame,
                            window: window,
                            dragPreviewData: $dragPreviewData,
                            onPreviewUpdate: onPreviewUpdate,
                            previewItemID: $previewItemID,
                            isPreviewPopoverPresented: $isPreviewPopoverPresented
                        )
                    } else {
                        ItemCompactColumn(
                            items: filteredItems,
                            pinboardSelectionKey: pinboardSelectionKey,
                            pinboards: pinboards,
                            lockedPinboardIDs: lockedPinboardIDs,
                            selectedItemIDs: selectedItemIDs,
                            editingItemID: editingItemID,
                            allowPinning: allowPinning,
                            readOnly: readOnly,
                            layoutAxis: layoutAxis,
                            clipItemEditor: clipItemEditor,
                            isDragEnabled: isDragEnabled,
                            isReorderingEnabled: isReorderingEnabled,
                            onPaste: actions.onPaste,
                            onPastePlainText: actions.onPastePlainText,
                            onCopy: actions.onCopy,
                            onDelete: actions.onDelete,
                            onTogglePin: actions.onTogglePin,
                            onConvertType: actions.onConvertType,
                            onMoveToPinboard: actions.onMoveToPinboard,
                            onCreatePinboard: actions.onCreatePinboard,
                            onEdit: actions.onEdit,
                            onRename: actions.onRename,
                            onCommitRename: actions.onCommitRename,
                            onTap: actions.onTap,
                            onDoubleTap: actions.onDoubleTap,
                            onReorder: actions.onReorder,
                            onReorderEnd: actions.onReorderEnd,
                            onDropToPinboard: actions.onDropToPinboard,
                            onDropToAll: actions.onDropToAll,
                            onPasteOutside: actions.onPasteOutside,
                            onBeginNativeDrag: actions.onBeginNativeDrag,
                            isNativeDragActive: actions.isNativeDragActive,
                            onPinboardDropTargetChanged: actions.onPinboardDropTargetChanged,
                            coordinateSpaceName: coordinateSpaceName,
                            pinboardFrames: pinboardFrames,
                            allPinboardFrame: allPinboardFrame,
                            window: window,
                            dragPreviewData: $dragPreviewData,
                            onPreviewUpdate: onPreviewUpdate,
                            previewItemID: $previewItemID,
                            isPreviewPopoverPresented: $isPreviewPopoverPresented
                        )
                    }
                }
                .id(pinboardSelectionKey)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .animation(OverlayAnimation.cardSpring, value: pinboardSelectionKey)
        .animation(OverlayAnimation.standardTransition, value: isSelectedPinboardAwaitingUnlock)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if readOnly {
                ReadOnlyHintBadge()
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
        }

    }
}

private struct OverlayEmptyStateView: View {
    let isSearchActive: Bool
    let selectedPinboardID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            Text(emptyStateTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var emptyStateIcon: String {
        if isSearchActive {
            return "magnifyingglass"
        }
        if selectedPinboardID != nil {
            return "square.stack.3d.up.slash"
        }
        return "clipboard"
    }

    private var emptyStateTitle: String {
        if isSearchActive {
            return "No matches"
        }
        if selectedPinboardID != nil {
            return "Pinboard is empty"
        }
        return "All items are empty"
    }
}

private struct LockedPinboardOverlayView: View {
    let title: String
    let canUnlock: Bool
    let isAuthenticating: Bool
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
                .contentTransition(.symbolEffect(.replace))

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: onUnlock) {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canUnlock)
                .accessibilityIdentifier("overlay.pinboard.unlock")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct ReadOnlyHintBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 10, weight: .semibold))
            Text("View only: editing actions are disabled")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.14))
        )
    }
}
