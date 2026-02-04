import AppKit
import ClipboardCore
import ClipboardMacServices
import CoreData
import SwiftUI

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
    let clipItemEditor: any ClipItemEditing
    let isDragEnabled: Bool
    let isReorderingEnabled: Bool

    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
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
                        ItemCardRow(
                            items: filteredItems,
                            pinboards: pinboards,
                            lockedPinboardIDs: lockedPinboardIDs,
                            selectedPinboardID: selectedPinboardID,
                            mode: mode,
                            selectedItemIDs: selectedItemIDs,
                            editingItemID: editingItemID,
                            allowPinning: allowPinning,
                            clipItemEditor: clipItemEditor,
                            isDragEnabled: isDragEnabled,
                            isReorderingEnabled: isReorderingEnabled,
                            onPaste: onPaste,
                            onPastePlainText: onPastePlainText,
                            onCopy: onCopy,
                            onDelete: onDelete,
                            onTogglePin: onTogglePin,
                            onMoveToPinboard: onMoveToPinboard,
                            onCreatePinboard: onCreatePinboard,
                            onEdit: onEdit,
                            onRename: onRename,
                            onCommitRename: onCommitRename,
                            onTap: onTap,
                            onDoubleTap: onDoubleTap,
                            onReorder: onReorder,
                            onReorderEnd: onReorderEnd,
                            onDropToPinboard: onDropToPinboard,
                            onDropToAll: onDropToAll,
                            onPasteOutside: onPasteOutside,
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
                            pinboards: pinboards,
                            lockedPinboardIDs: lockedPinboardIDs,
                            selectedItemIDs: selectedItemIDs,
                            editingItemID: editingItemID,
                            allowPinning: allowPinning,
                            clipItemEditor: clipItemEditor,
                            isDragEnabled: isDragEnabled,
                            isReorderingEnabled: isReorderingEnabled,
                            onPaste: onPaste,
                            onPastePlainText: onPastePlainText,
                            onCopy: onCopy,
                            onDelete: onDelete,
                            onTogglePin: onTogglePin,
                            onMoveToPinboard: onMoveToPinboard,
                            onCreatePinboard: onCreatePinboard,
                            onEdit: onEdit,
                            onRename: onRename,
                            onCommitRename: onCommitRename,
                            onTap: onTap,
                            onDoubleTap: onDoubleTap,
                            onReorder: onReorder,
                            onReorderEnd: onReorderEnd,
                            onDropToPinboard: onDropToPinboard,
                            onDropToAll: onDropToAll,
                            onPasteOutside: onPasteOutside,
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
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelectedPinboardAwaitingUnlock)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(pinboardSelectionKey)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.14), value: pinboardSelectionKey)
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
            Image(systemName: isAuthenticating ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
                .contentTransition(.symbolEffect(.replace))

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Button(action: onUnlock) {
                if isAuthenticating {
                    ProgressView("Authenticating...")
                } else {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating || !canUnlock)
            .accessibilityIdentifier("overlay.pinboard.unlock")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
