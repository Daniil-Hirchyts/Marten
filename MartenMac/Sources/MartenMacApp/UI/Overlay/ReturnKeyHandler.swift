import MartenCore

@MainActor
final class ReturnKeyHandler {
    weak var viewModel: OverlayViewModel?
    weak var modifierMonitor: ModifierKeyMonitor?
    let getFilteredItems: () -> [ClipItem]

    init(
        viewModel: OverlayViewModel,
        modifierMonitor: ModifierKeyMonitor,
        getFilteredItems: @escaping () -> [ClipItem]
    ) {
        self.viewModel = viewModel
        self.modifierMonitor = modifierMonitor
        self.getFilteredItems = getFilteredItems
    }

    func handleReturnKey() {
        guard let viewModel = viewModel, let modifierMonitor = modifierMonitor else { return }
        viewModel.handleReturnKey(
            orderedItems: getFilteredItems(),
            isShiftPressed: modifierMonitor.isShiftPressed
        )
    }
}
