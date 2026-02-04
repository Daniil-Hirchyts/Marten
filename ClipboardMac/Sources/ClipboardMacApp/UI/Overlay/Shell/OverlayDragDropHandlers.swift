import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

extension OverlayShellView {
    func handleDropToPinboard(_ item: ClipItem, _ pinboardID: NSManagedObjectID) {
        actionHandlers.handleDropToPinboard(
            item,
            pinboardID,
            pinboards: pinboards,
            onClearSelection: viewModel.clearSelection
        )
    }

    func handleDropToAll(_ item: ClipItem) {
        actionHandlers.handleDropToAll(
            item,
            selectedPinboardID: searchModel.selectedPinboardID,
            pinboards: pinboards,
            onClearSelection: viewModel.clearSelection
        )
    }
}

