@preconcurrency import ClipboardCore
import SwiftUI

/// Handles pinboard locking and unlocking operations
@MainActor
struct OverlayPinboardLockHandler {
    let pinboardLockController: PinboardLockController
    let onClearSelection: () -> Void
    let onClosePreview: () -> Void

    func setPinboardLock(_ pinboard: Pinboard, enabled: Bool) {
        if !enabled && !pinboardLockController.canAccess(pinboardID: pinboard.id) {
            requestPinboardUnlock(pinboard, selectedPinboardID: nil)
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            pinboardLockController.setLockEnabled(enabled, pinboardID: pinboard.id)
        }

        // If locking the currently selected pinboard, clear selection
        onClearSelection()
        onClosePreview()
    }

    func lockPinboardNow(_ pinboard: Pinboard, selectedPinboardID: UUID?) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pinboardLockController.lockNow(pinboardID: pinboard.id)
        }

        if selectedPinboardID == pinboard.id {
            onClearSelection()
            onClosePreview()
        }
    }

    func requestPinboardUnlock(_ pinboard: Pinboard, selectedPinboardID: UUID?) {
        Task { @MainActor in
            let unlocked = await pinboardLockController.unlock(
                pinboardID: pinboard.id,
                pinboardName: pinboard.name
            )

            if unlocked, selectedPinboardID == pinboard.id {
                onClearSelection()
            }
        }
    }

    func isItemVisible(_ item: ClipItem, selectedPinboardID: UUID?) -> Bool {
        if let selectedPinboardID {
            guard item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false else {
                return false
            }
            return selectedPinboardIsAccessible(selectedPinboardID)
        }
        return !isItemHiddenInAllPinboard(item)
    }

    private func isItemHiddenInAllPinboard(_ item: ClipItem) -> Bool {
        let customPinboards = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        guard !customPinboards.isEmpty else { return false }

        return customPinboards.contains { pinboard in
            pinboardLockController.isLocked(pinboardID: pinboard.id)
                && !pinboardLockController.canAccess(pinboardID: pinboard.id)
        }
    }

    private func selectedPinboardIsAccessible(_ pinboardID: UUID?) -> Bool {
        guard let pinboardID else { return true }
        return pinboardLockController.canAccess(pinboardID: pinboardID)
    }
}
