import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import OSLog
import SwiftUI

struct PinboardRenameState {
    var id: NSManagedObjectID?
    var name: String = ""
    var colorHex: String = PinboardPalette.defaultHex
    var iconName: String?
    var isCreating: Bool = false
    var pendingItem: ClipItem?
}

struct VerticalPinboardCreateState {
    var isPresented: Bool = false
    var draftName: String = ""
    var draftColorHex: String = PinboardPalette.defaultHex
    var draftIconName: String?
    var shouldPresentStylePicker: Bool = false
}

struct VerticalPinboardEditState {
    var isPresented: Bool = false
    var draftName: String = ""
    var draftColorHex: String = PinboardPalette.defaultHex
    var draftIconName: String?
    var shouldPresentStylePicker: Bool = false
}

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
    @ObservedObject var screenSharingManager: ScreenSharingManager
    @ObservedObject var pasteboardMonitor: PasteboardMonitor

    @State var pinboardRenameState = PinboardRenameState()
    @State var verticalPinboardCreateState = VerticalPinboardCreateState()
    @State var verticalPinboardEditState = VerticalPinboardEditState()
    @State var isVerticalPinboardDropdownPresented = false

    @State var renameItemID: NSManagedObjectID?
    @State var shareSheetPinboard: Pinboard?

    @AppStorage(OverlayLayoutSettings.Keys.overlayScreenEdge)
    var overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue

    @FocusState var searchFocused: Bool
    @FocusState var verticalPinboardNameFocused: Bool
    @FocusState var verticalPinboardEditNameFocused: Bool
    @State var isSearchExpanded = false
    @State var pinboardTabsContentWidth: CGFloat = 0
    @State var isFilterPopoverPresented = false
    @State var cachedFilteredItems: [ClipItem] = []
    @State var lastFilterInputHash: Int = 0
    @State var isOptionsHovered = false

    @State var window: NSWindow?
    @State var itemDragPinboardDropTargetID: NSManagedObjectID?

    // Compact pinboard bar drag-reorder state
    @State var compactDragState: PinboardTabDragState?
    @State var compactDropTarget: PinboardTabDropTarget?
    @State var compactDragOpacity: Double = 0
    @State var compactPillFrames: [NSManagedObjectID: CGRect] = [:]
    @State var compactCachedOrderedFrames: [(item: Pinboard, frame: CGRect)]?

    let itemOperationsHandler: any ItemOperating
    let pinboardManager: any PinboardManaging
    let sharingRepository: (any PinboardSharingRepositoryProtocol)?
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
            NSSortDescriptor(key: "modifiedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ],
        predicate: NSPredicate(format: "isTransient == NO"),
        animation: nil
    )
    var items: FetchedResults<ClipItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)],
        animation: nil
    )
    var pinboards: FetchedResults<Pinboard>

    init(persistence: PersistenceController, dependencies: OverlayDependencies) {
        guard let store = dependencies.clipItemStore as? ClipItemStore else {
            preconditionFailure("OverlayDependencies.clipItemStore must be a ClipItemStore")
        }
        self.clipItemEditor = store
        self.itemOperationsHandler = dependencies.itemOperations
        self.pinboardManager = dependencies.pinboards
        self.sharingRepository = dependencies.sharing
        self.screenSharingManager = dependencies.screenSharingManager
        self.pasteboardMonitor = dependencies.pasteboardMonitor
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
        lifecycleModifiedContent
            .onChange(of: filterInputHash) { _, newHash in
                if newHash != lastFilterInputHash {
                    lastFilterInputHash = newHash
                    cachedFilteredItems = computeFilteredItems()
                    viewModel.ensureDefaultSelection(in: cachedFilteredItems)  // prunes stale selections only
                }
            }
            .onChange(of: viewModel.selectedItemIDs) { handleSelectionChange($0, $1) }
            .onChange(of: overlayLayoutAxis) { handleOverlayLayoutAxisChange($0, $1) }
            .onChange(of: pinboardLockController.isAuthenticating) { _, newValue in
                viewModel.isAuthenticating = newValue
            }
            .onReceive(eventBroadcaster.events, perform: handleBroadcasterEvent)
    }

    private var lifecycleModifiedContent: some View {
        mainContent
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
            .onChange(of: window) { handleWindowChange($0, $1) }
            .onChange(of: searchModel.selectedPinboardID) { handlePinboardSelectionChange($0, $1) }
            .onChange(of: selectedPinboardIsAccessible) { handlePinboardAccessibilityChange($0, $1) }
            .onChange(of: isSearchExpanded) { handleSearchExpandedChange($0, $1) }
            .onChange(of: isFilterPopoverPresented) { handleFilterPopoverPresentedChange($0, $1) }
            .onChange(of: keyHandlerRefreshToken) { handleKeyHandlerRefresh($0, $1) }
            .onChange(of: visiblePinboardIDs) { handleVisiblePinboardsChange($0, $1) }
            .onChange(of: itemsChangeSignature) { handleItemsSourceAppsChange($0, $1) }
    }

    private var mainContent: some View {
        ZStack {
            backgroundView.ignoresSafeArea()

            layoutContent
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
        .clipShape(RoundedRectangle(cornerRadius: overlayLayoutAxis == .compact ? 20 : 34, style: .continuous))
        .onChange(of: dragCoordinator.dragPreviewData) { newData, _ in
            dragCoordinator.updateDragPreviewWindow(newData, parentWindow: window)
        }
        .alert("Accessibility Permission Required", isPresented: $viewModel.showAccessibilityAlert) {
            Button("Open System Settings") { viewModel.requestAccessibility() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marten needs Accessibility permission to paste into other apps.")
        }
        .environmentObject(frameCoordinator)
    }

    @ViewBuilder
    private var layoutContent: some View {
        if overlayLayoutAxis == .compact {
            ZStack(alignment: .top) {
                // Items fill entire area, edge-to-edge
                itemGridSection
                    .mask(
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 22)
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 22)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 22)
                            Color.clear
                                .frame(height: 22)
                        }
                    )

                // Pinboard bar floating at top
                VStack(spacing: 0) {
                    compactPinboardBar
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    Spacer(minLength: 0)

                    // Toolbar floating at bottom
                    verticalToolbarRow
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                }
            }
        } else if overlayLayoutAxis == .horizontal {
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
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 26)
                            Color.black
                        }
                    )
            }
            .padding(.top, 10)
        }
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
            readOnly: selectedPinboardIsReadOnly,
            clipItemEditor: clipItemEditor,
            isDragEnabled: isDragEnabled,
            isReorderingEnabled: isReorderingEnabled,
            actions: ItemGridActionHandlers(
                onPaste: handleItemPaste,
                onPastePlainText: handleItemPastePlainText,
                onCopy: handleCopyItem,
                onDelete: handleDeleteItem,
                onTogglePin: handleTogglePin,
                onConvertType: handleConvertItemType,
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
                onBeginNativeDrag: handleBeginNativeDrag,
                isNativeDragActive: { [dragCoordinator] in dragCoordinator.isNativeDragActive },
                onPinboardDropTargetChanged: { itemDragPinboardDropTargetID = $0 }
            ),
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
