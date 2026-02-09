import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import SwiftUI

extension OverlayShellView {
    var shouldShowVerticalPinboardEditButton: Bool {
        selectedCustomPinboard != nil
    }

    func nextAvailablePinboardColorHex() -> String {
        let usedColors = Set(pinboards.map { $0.colorHex })
        let availableColors = PinboardPalette.colors.filter { !usedColors.contains($0) }
        return availableColors.first ?? PinboardPalette.defaultHex
    }

    func nextAvailablePinboardName(base: String = "New Pinboard") -> String {
        let normalizedNames = Set(
            visiblePinboards.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        if !normalizedNames.contains(base.lowercased()) {
            return base
        }

        var index = 2
        while normalizedNames.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    var verticalPinboardLabel: String {
        selectedCustomPinboard?.name ?? "All Items"
    }

    var lockedPinboardTitle: String {
        guard let selectedCustomPinboard else { return "Pinboard is locked" }
        return "\"\(selectedCustomPinboard.name)\" is locked"
    }

    var allItemsVisibleInAllPinboard: [ClipItem] {
        Array(items).filter { lockHandler.isItemVisible($0, selectedPinboardID: nil) }
    }

    func handleUnlockTap() {
        guard let selectedCustomPinboard else { return }
        lockHandler.requestPinboardUnlock(selectedCustomPinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func ensureValidSelection() {
        guard let selectedPinboardID = searchModel.selectedPinboardID else { return }
        guard visiblePinboards.contains(where: { $0.id == selectedPinboardID }) else {
            searchModel.selectedPinboardID = nil
            return
        }
    }

    func announceOverlayItemCount() {
        let announcement = "Marten, \(filteredItems.count) items"
        let element: Any = window ?? NSApp ?? NSApplication.shared
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement]
        )
    }

    func openSettingsLegacy() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func handleOverlayTap(at location: CGPoint) {
        if previewCoordinator.isPreviewPopoverPresented {
            // Let NSPopover handle outside-click dismissal and keep interactions
            // inside the preview responsive.
            return
        }

        if isSearchExpanded,
            let searchFieldFrame = dragCoordinator.searchFieldFrame,
            !searchFieldFrame.contains(location)
        {
            closeSearchIfEmpty()
        }

        guard pinboardRenameState.isCreating || pinboardRenameState.id != nil,
            let pinboardEditorFrame = dragCoordinator.pinboardEditorFrame,
            !pinboardEditorFrame.contains(location)
        else { return }

        if pinboardRenameState.isCreating && pinboardRenameState.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handlePinboardCancel()
        } else {
            handlePinboardCommit()
        }
    }
}
