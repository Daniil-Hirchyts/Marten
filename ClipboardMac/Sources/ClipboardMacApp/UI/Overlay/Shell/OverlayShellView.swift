import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

struct OverlayShellView: View {
    let clipItemEditor: any ClipItemEditing
    let overlayCoordinateSpaceName = "OverlaySpace"
    let headerButtonSize: CGFloat = 30
    let headerButtonIconSize: CGFloat = 14
    let searchCollapsedWidth: CGFloat = 30
    let searchExpandedWidth: CGFloat = 220
    var headerSideWidth: CGFloat { searchExpandedWidth + 20 }

    @EnvironmentObject var viewModel: OverlayViewModel
    @Environment(\.clipboardEventBroadcaster) var eventBroadcaster
    @StateObject var modifierMonitor = ModifierKeyMonitor()
    @StateObject var searchModel: OverlaySearchViewModel
    @StateObject var frameCoordinator = FrameCoordinator()
    @StateObject var dragCoordinator = DragCoordinator()
    @StateObject var pinboardLockController = PinboardLockController()
    @StateObject var previewCoordinator: OverlayPreviewCoordinator

    @State var renamePinboardID: NSManagedObjectID?
    @State var renamePinboardName = ""
    @State var renamePinboardColor = PinboardPalette.defaultHex
    @State var renamePinboardIcon: String?
    @State var isCreatingPinboard = false
    @State var pendingPinboardItem: ClipItem?
    @State var isVerticalPinboardCreatePresented = false
    @State var verticalPinboardDraftName = ""
    @State var verticalPinboardDraftColor = PinboardPalette.defaultHex
    @State var verticalPinboardDraftIcon: String?
    @State var shouldPresentVerticalPinboardStylePicker = false
    @State var isVerticalPinboardEditPresented = false
    @State var verticalPinboardEditDraftName = ""
    @State var verticalPinboardEditDraftColor = PinboardPalette.defaultHex
    @State var verticalPinboardEditDraftIcon: String?
    @State var shouldPresentVerticalPinboardEditStylePicker = false
    @State var isVerticalPinboardDropdownPresented = false

    @State var renameItemID: NSManagedObjectID?

    @AppStorage(OverlayLayoutSettings.Keys.overlayScreenEdge)
    var overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue
    @FocusState var searchFocused: Bool
    @FocusState var verticalPinboardNameFocused: Bool
    @FocusState var verticalPinboardEditNameFocused: Bool
    @State var isSearchExpanded = false
    @State var isFilterPopoverPresented = false

    @State var window: NSWindow?

    let itemOperationsHandler: any ItemOperating
    let pinboardManager: any PinboardManaging
    let pasteStackManager = PasteStackManager()

    var actionHandlers: OverlayActionHandlers {
        OverlayActionHandlers(
            itemOperationsHandler: itemOperationsHandler,
            pinboardManager: pinboardManager,
            pasteStackManager: pasteStackManager,
            pinboardLockController: pinboardLockController,
            searchModel: searchModel
        )
    }

    var lockHandler: OverlayPinboardLockHandler {
        OverlayPinboardLockHandler(
            pinboardLockController: pinboardLockController,
            onClearSelection: viewModel.clearSelection,
            onClosePreview: previewCoordinator.closePreview
        )
    }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "displayOrder", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ],
        predicate: NSPredicate(format: "isTransient == NO"),
        animation: .default
    )
    var items: FetchedResults<ClipItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)],
        animation: .default
    )
    var pinboards: FetchedResults<Pinboard>

    init(persistence: PersistenceController, dependencies: OverlayDependencies) {
        guard let store = dependencies.clipItemStore as? ClipItemStore else {
            preconditionFailure("OverlayDependencies.clipItemStore must be a ClipItemStore")
        }
        self.clipItemEditor = store
        self.itemOperationsHandler = dependencies.itemOperations
        self.pinboardManager = dependencies.pinboards
        _searchModel = StateObject(wrappedValue: OverlaySearchViewModel(store: store))
        _previewCoordinator = StateObject(wrappedValue: dependencies.previewCoordinator)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 0, style: .continuous))
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
        }
    }

    var body: some View {
        mainContent
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            .onChange(of: window) { handleWindowChange($0, $1) }
            .onChange(of: searchModel.selectedPinboardID) { handlePinboardSelectionChange($0, $1) }
            .onChange(of: selectedPinboardIsAccessible) { handlePinboardAccessibilityChange($0, $1) }
            .onChange(of: isSearchExpanded) { handleSearchExpandedChange($0, $1) }
            .onChange(of: keyHandlerRefreshToken) { handleKeyHandlerRefresh($0, $1) }
            .onChange(of: visiblePinboardIDs) { handleVisiblePinboardsChange($0, $1) }
            .onChange(of: itemsSourceAppsHash) { handleItemsSourceAppsChange($0, $1) }
            .onChange(of: filteredItemSelectionSignature) { handleFilteredItemsChange($0, $1) }
            .onChange(of: viewModel.selectedItemIDs) { handleSelectionChange($0, $1) }
            .onChange(of: overlayLayoutAxis) { handleOverlayLayoutAxisChange($0, $1) }
            .onChange(of: pinboardLockController.isAuthenticating) { _, newValue in
                viewModel.isAuthenticating = newValue
            }
            .onReceive(eventBroadcaster.events, perform: handleBroadcasterEvent)
    }

    private var mainContent: some View {
        ZStack {
            backgroundView.ignoresSafeArea()

            Group {
                if overlayLayoutAxis == .horizontal {
                    VStack(alignment: .leading, spacing: 14) {
                        horizontalHeaderBar
                        itemGridSection
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        verticalToolbarRow
                        verticalPinboardPickerRow
                        itemGridSection
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ResizeHandleView(window: window)
        }
        .coordinateSpace(name: overlayCoordinateSpaceName)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .named(overlayCoordinateSpaceName)) { handleOverlayTap(at: $0) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(overlayCoordinateSpaceName))
                .onEnded { handleOverlayTap(at: $0.location) }
        )
        .background(WindowAccessor(window: $window))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onChange(of: dragCoordinator.dragPreviewData) { newData, _ in
            dragCoordinator.updateDragPreviewWindow(newData, parentWindow: window)
        }
        .alert("Accessibility Permission Required", isPresented: $viewModel.showAccessibilityAlert) {
            Button("Open System Settings") { viewModel.requestAccessibility() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste needs Accessibility permission to paste into other apps.")
        }
        .environmentObject(frameCoordinator)
    }

    private var itemGridSection: some View {
        ItemGridSection(
            layoutAxis: overlayLayoutAxis,
            isSelectedPinboardAwaitingUnlock: isSelectedPinboardAwaitingUnlock,
            lockedPinboardTitle: lockedPinboardTitle,
            canUnlockLockedPinboard: selectedCustomPinboard != nil,
            isAuthenticatingLock: pinboardLockController.isAuthenticating,
            onUnlockLockedPinboard: handleUnlockTap,
            filteredItems: filteredItems,
            isSearchActive: isSearchActive,
            selectedPinboardID: searchModel.selectedPinboardID,
            pinboards: visiblePinboards,
            lockedPinboardIDs: lockedPinboardIDs,
            mode: viewModel.mode,
            selectedItemIDs: viewModel.selectedItemIDs,
            editingItemID: renameItemID,
            allowPinning: allowPinning,
            clipItemEditor: clipItemEditor,
            isDragEnabled: isDragEnabled,
            isReorderingEnabled: isReorderingEnabled,
            onPaste: handleItemPaste,
            onPastePlainText: handleItemPastePlainText,
            onCopy: handleCopyItem,
            onDelete: handleDeleteItem,
            onTogglePin: handleTogglePin,
            onMoveToPinboard: handleMoveToPinboard,
            onCreatePinboard: beginPinboardCreate,
            onEdit: handleOpenEditor,
            onRename: { renameItemID = $0.objectID },
            onCommitRename: handleCommitItemRename,
            onTap: handleCardTap,
            onDoubleTap: handleCardDoubleTap,
            onReorder: handleReorderItems,
            onReorderEnd: pinboardManager.saveChanges,
            onDropToPinboard: handleDropToPinboard,
            onDropToAll: handleDropToAll,
            onPasteOutside: handlePasteOutside,
            coordinateSpaceName: overlayCoordinateSpaceName,
            pinboardFrames: dragCoordinator.pinboardFrames,
            allPinboardFrame: dragCoordinator.allPinboardFrame,
            window: window,
            dragPreviewData: $dragCoordinator.dragPreviewData,
            onPreviewUpdate: { dragCoordinator.updateDragPreviewWindow($0, parentWindow: window) },
            previewItemID: $previewCoordinator.previewItemID,
            isPreviewPopoverPresented: $previewCoordinator.isPreviewPopoverPresented,
            pinboardSelectionKey: pinboardSelectionKey
        )
    }
}
