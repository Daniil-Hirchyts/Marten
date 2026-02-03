import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import SwiftUI

struct OverlayShellView: View {
    private let clipItemEditor: any ClipItemEditing
    private let overlayCoordinateSpaceName = "OverlaySpace"
    private let headerButtonSize: CGFloat = 30
    private let headerButtonIconSize: CGFloat = 14
    private let searchCollapsedWidth: CGFloat = 30
    private let searchExpandedWidth: CGFloat = 220
    private var headerSideWidth: CGFloat { searchExpandedWidth + 20 }

    // View Models & State Objects
    @EnvironmentObject var viewModel: OverlayViewModel
    @Environment(\.clipboardEventBroadcaster) var eventBroadcaster
    @StateObject var modifierMonitor = ModifierKeyMonitor()
    @StateObject var searchModel: OverlaySearchViewModel
    @StateObject var frameCoordinator = FrameCoordinator()
    @StateObject var dragCoordinator = DragCoordinator()
    @StateObject var pinboardLockController = PinboardLockController()
    @StateObject var previewCoordinator: OverlayPreviewCoordinator

    // Pinboard State
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

    // Item State
    @State var renameItemID: NSManagedObjectID?

    // Search State
    @AppStorage(OverlayLayoutSettings.Keys.overlayScreenEdge)
    var overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue
    @FocusState var searchFocused: Bool
    @FocusState var verticalPinboardNameFocused: Bool
    @FocusState var verticalPinboardEditNameFocused: Bool
    @State var isSearchExpanded = false
    @State var isFilterPopoverPresented = false

    // Window State
    @State var window: NSWindow?

    // Handlers
    private let itemOperationsHandler: ItemOperationsHandler
    private let pinboardManager: PinboardManager
    private let pasteStackManager = PasteStackManager()

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

    init(persistence: PersistenceController, store: ClipItemStore) {
        let appleIntelligence = AppleIntelligenceTextService()
        let itemEditorWindowController = ItemEditorWindowController(
            clipItemEditor: store,
            appleIntelligence: appleIntelligence
        )
        self.clipItemEditor = store
        self.itemOperationsHandler = ItemOperationsHandler(store: store)
        self.pinboardManager = PinboardManager(store: store, persistence: persistence)
        _searchModel = StateObject(wrappedValue: OverlaySearchViewModel(store: store))
        _previewCoordinator = StateObject(
            wrappedValue: OverlayPreviewCoordinator(itemEditorWindowController: itemEditorWindowController)
        )
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
            .onChange(of: viewModel.selectedItemIDs) { handleSelectionChange($0, $1) }
            .onChange(of: overlayLayoutAxis) { handleOverlayLayoutAxisChange($0, $1) }
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

    private var horizontalHeaderBar: some View {
        ZStack(alignment: .center) {
            PinboardTabBarSection(
                pinboards: visiblePinboards,
                selectedID: searchModel.selectedPinboardID,
                isLocked: { pinboardLockController.isLocked(pinboardID: $0.id) },
                isUnlocked: { pinboardLockController.canAccess(pinboardID: $0.id) },
                editingID: $renamePinboardID,
                isCreating: $isCreatingPinboard,
                draftName: $renamePinboardName,
                draftColor: $renamePinboardColor,
                draftIcon: $renamePinboardIcon,
                isGlobalDragActive: dragCoordinator.dragPreviewData != nil,
                window: window,
                onPreviewUpdate: { dragCoordinator.updatePinboardDragPreviewWindow($0, parentWindow: window) },
                onSelect: handlePinboardSelect,
                onCreate: handlePinboardCreateStart,
                onSetLockEnabled: handleSetPinboardLock,
                onUnlock: handleRequestPinboardUnlock,
                onLockNow: handleLockPinboardNow,
                onRename: handlePinboardRenameStart,
                onColorChange: pinboardManager.changePinboardColor,
                onIconChange: pinboardManager.changePinboardIcon,
                onDelete: handleDeletePinboard,
                onReorder: handlePinboardReorder,
                onReorderEnd: pinboardManager.saveChanges,
                onMoveItem: handlePinboardMoveItem,
                onCommit: handlePinboardCommit,
                onCancel: handlePinboardCancel,
                coordinateSpaceName: overlayCoordinateSpaceName,
                horizontalPadding: headerSideWidth,
                rowHeight: headerButtonSize,
                onPinboardLayoutChange: handlePinboardLayoutChange,
                onSearchFieldFrameChange: { frame in
                    DispatchQueue.main.async { dragCoordinator.updateSearchFieldFrame(frame) }
                }
            )

            OverlaySearchBarView(
                isSearchExpanded: $isSearchExpanded,
                isFilterPopoverPresented: $isFilterPopoverPresented,
                searchText: $searchModel.searchText,
                searchFocused: $searchFocused,
                dateFilter: $searchModel.dateFilter,
                typeFilters: $searchModel.typeFilters,
                appFilters: $searchModel.appFilters,
                appOptions: searchModel.appOptions,
                hasActiveFilters: searchModel.hasActiveFilters,
                headerButtonSize: headerButtonSize,
                headerButtonIconSize: headerButtonIconSize,
                searchCollapsedWidth: searchCollapsedWidth,
                searchExpandedWidth: searchExpandedWidth,
                overlayCoordinateSpaceName: overlayCoordinateSpaceName,
                onSearchButtonTap: handleSearchButtonTap,
                onSearchClear: handleSearchClear,
                onClearFilters: searchModel.clearFilters
            )
            .frame(width: headerSideWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)

            HStack {
                Spacer()
                settingsButton
            }
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 14)
        .frame(height: headerButtonSize)
        .zIndex(1)
    }

    private var verticalToolbarRow: some View {
        HStack(spacing: 8) {
            OverlaySearchBarView(
                isSearchExpanded: $isSearchExpanded,
                isFilterPopoverPresented: $isFilterPopoverPresented,
                searchText: $searchModel.searchText,
                searchFocused: $searchFocused,
                dateFilter: $searchModel.dateFilter,
                typeFilters: $searchModel.typeFilters,
                appFilters: $searchModel.appFilters,
                appOptions: searchModel.appOptions,
                hasActiveFilters: searchModel.hasActiveFilters,
                headerButtonSize: headerButtonSize,
                headerButtonIconSize: headerButtonIconSize,
                searchCollapsedWidth: searchCollapsedWidth,
                searchExpandedWidth: min(searchExpandedWidth, 260),
                overlayCoordinateSpaceName: overlayCoordinateSpaceName,
                onSearchButtonTap: handleSearchButtonTap,
                onSearchClear: handleSearchClear,
                onClearFilters: searchModel.clearFilters
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsButton
        }
        .padding(.horizontal, 14)
        .onPreferenceChange(SearchFieldFrameKey.self) { frame in
            DispatchQueue.main.async { dragCoordinator.updateSearchFieldFrame(frame) }
        }
    }

    private var verticalPinboardPickerRow: some View {
        HStack(spacing: 8) {
            verticalPinboardPickerMenu
                .frame(maxWidth: .infinity, alignment: .leading)

            if shouldShowVerticalPinboardEditButton {
                verticalPinboardEditButton
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 14)
    }

    private var verticalPinboardPickerMenu: some View {
        Button {
            isVerticalPinboardDropdownPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                if let selectedCustomPinboard {
                    PinboardIndicator(
                        colorHex: selectedCustomPinboard.colorHex,
                        sign: selectedCustomPinboard.iconName,
                        size: 15
                    )
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, height: 15)
                }

                Text(verticalPinboardLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .frame(height: headerButtonSize)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassNavigationStyle()
                } else {
                    Capsule()
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
                }
            }
            .overlay {
                if #available(macOS 26.0, *) {
                    EmptyView()
                } else {
                    Capsule()
                        .stroke(Color.white.opacity(DesignTokens.Opacity.borderStrong), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .popover(isPresented: $isVerticalPinboardDropdownPresented, arrowEdge: .top) {
            verticalPinboardDropdownContent
        }
        .popover(isPresented: $isVerticalPinboardCreatePresented, arrowEdge: .top) {
            verticalPinboardCreatePopover
        }
        .accessibilityIdentifier("overlay.pinboard.picker")
        .accessibilityLabel("Pinboard")
    }

    private var verticalPinboardDropdownContent: some View {
        VStack(spacing: 0) {
            Button {
                handlePinboardSelect(nil)
                isVerticalPinboardDropdownPresented = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, height: 15)
                    Text("All Items")
                    Spacer(minLength: 0)
                    if searchModel.selectedPinboardID == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            ForEach(visiblePinboards) { pinboard in
                let isSelected = searchModel.selectedPinboardID == pinboard.id
                Button {
                    handlePinboardSelect(pinboard.id)
                    isVerticalPinboardDropdownPresented = false
                } label: {
                    HStack(spacing: 8) {
                        PinboardIndicator(
                            colorHex: pinboard.colorHex,
                            sign: pinboard.iconName,
                            size: 15
                        )
                        Text(pinboard.name)
                        Spacer(minLength: 0)
                        if pinboardLockController.isLocked(pinboardID: pinboard.id) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            Divider()
                .padding(.vertical, 2)

            Button {
                isVerticalPinboardDropdownPresented = false
                DispatchQueue.main.async {
                    handleCreatePinboardFromVerticalPicker()
                }
            } label: {
                HStack(spacing: 8) {
                    PinboardIndicator(
                        colorHex: nextAvailablePinboardColorHex(),
                        sign: nil,
                        size: 15
                    )
                    Text("New Pinboard...")
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var verticalPinboardEditButton: some View {
        Button {
            presentVerticalPinboardEdit()
        } label: {
            Text("Edit")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isVerticalPinboardEditPresented, arrowEdge: .top) {
            verticalPinboardEditPopover
        }
        .accessibilityIdentifier("overlay.pinboard.picker.edit")
        .accessibilityLabel("Edit selected pinboard")
    }

    private var verticalPinboardCreatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Pinboard")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 8) {
                PinboardStylePickerButton(
                    selectedColorHex: verticalPinboardDraftColor,
                    selectedSign: verticalPinboardDraftIcon,
                    shouldPresentOnAppear: $shouldPresentVerticalPinboardStylePicker,
                    onColorSelect: { verticalPinboardDraftColor = $0 },
                    onSignSelect: { verticalPinboardDraftIcon = $0 }
                )

                TextField("Pinboard name", text: $verticalPinboardDraftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($verticalPinboardNameFocused)
                    .accessibilityIdentifier("overlay.pinboard.verticalCreate.name")
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    cancelVerticalPinboardCreate()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    commitVerticalPinboardCreate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(verticalPinboardDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("overlay.pinboard.verticalCreate.commit")
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            DispatchQueue.main.async {
                verticalPinboardNameFocused = true
            }
        }
    }

    private var verticalPinboardEditPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Pinboard")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 8) {
                PinboardStylePickerButton(
                    selectedColorHex: verticalPinboardEditDraftColor,
                    selectedSign: verticalPinboardEditDraftIcon,
                    shouldPresentOnAppear: $shouldPresentVerticalPinboardEditStylePicker,
                    onColorSelect: { verticalPinboardEditDraftColor = $0 },
                    onSignSelect: { verticalPinboardEditDraftIcon = $0 }
                )

                TextField("Pinboard name", text: $verticalPinboardEditDraftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($verticalPinboardEditNameFocused)
                    .accessibilityIdentifier("overlay.pinboard.verticalEdit.name")
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    cancelVerticalPinboardEdit()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    commitVerticalPinboardEdit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(verticalPinboardEditDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("overlay.pinboard.verticalEdit.commit")
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            DispatchQueue.main.async {
                verticalPinboardEditNameFocused = true
            }
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        Group {
            if #available(macOS 14.0, *) {
                OverlaySettingsButton14(
                    closeOverlay: { viewModel.closeOverlayForSettings(completion: $0) },
                    label: AnyView(settingsIcon)
                )
            } else {
                Button { viewModel.closeOverlayForSettings(completion: openSettingsLegacy) }
                label: { settingsIcon }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("overlay.settings")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens settings")
    }

    @ViewBuilder
    private var settingsIcon: some View {
        if #available(macOS 26.0, *) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: headerButtonSize, height: headerButtonSize)
                .glassCircleButton()
                .contentShape(Circle())
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: headerButtonSize, height: headerButtonSize)
                .background(Circle().fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium)))
                .contentShape(Circle())
        }
    }
}

// MARK: - Lifecycle & Event Handlers

private extension OverlayShellView {
    func handleAppear() {
        searchFocused = true
        modifierMonitor.start()
        pinboardLockController.reconcile(validPinboardIDs: visiblePinboardIDs)
        ensureValidSelection()
        dragCoordinator.ensurePreviewWindow()
        dragCoordinator.ensurePinboardPreviewWindow()
        installKeyboardHandlers()
    }

    func handleDisappear() {
        modifierMonitor.stop()
        dragCoordinator.cleanupPreviewWindow()
        dragCoordinator.cleanupPinboardPreviewWindow()
        previewCoordinator.closePreview()

        if searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchExpanded = false
            searchFocused = false
        }
        isFilterPopoverPresented = false
        isCreatingPinboard = false
        renamePinboardID = nil
        renamePinboardIcon = nil
        isVerticalPinboardCreatePresented = false
        isVerticalPinboardDropdownPresented = false
        shouldPresentVerticalPinboardStylePicker = false
        isVerticalPinboardEditPresented = false
        shouldPresentVerticalPinboardEditStylePicker = false
    }

    func handleWindowChange(_ oldValue: NSWindow?, _ newValue: NSWindow?) {
        installKeyboardHandlers()
    }

    func handlePinboardSelectionChange(_ oldValue: UUID?, _ newValue: UUID?) {
        if oldValue != newValue {
            isVerticalPinboardEditPresented = false
            shouldPresentVerticalPinboardEditStylePicker = false
        }
        if isSelectedPinboardAwaitingUnlock {
            viewModel.clearSelection()
            previewCoordinator.closePreview()
        }
        if isFilterPopoverPresented {
            searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
        }
    }

    func handlePinboardAccessibilityChange(_ isAccessible: Bool, _ old: Bool) {
        if !isAccessible, searchModel.selectedPinboardID != nil {
            viewModel.clearSelection()
            previewCoordinator.closePreview()
        }
    }

    func handleSearchExpandedChange(_ expanded: Bool, _ old: Bool) {
        if !expanded {
            isFilterPopoverPresented = false
        }
    }

    func handleKeyHandlerRefresh(_ oldValue: String, _ newValue: String) {
        installKeyboardHandlers()
    }

    func handleVisiblePinboardsChange(_ oldValue: [UUID], _ newValue: [UUID]) {
        pinboardLockController.reconcile(validPinboardIDs: newValue)
        ensureValidSelection()
    }

    func handleItemsSourceAppsChange(_ oldValue: Int, _ newValue: Int) {
        if isFilterPopoverPresented {
            searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
        }
    }

    func handleSelectionChange(_ oldValue: Set<NSManagedObjectID>, _ newValue: Set<NSManagedObjectID>) {
        if previewCoordinator.isPreviewPopoverPresented {
            previewCoordinator.closePreview()
        }
    }

    func handleOverlayLayoutAxisChange(_ oldValue: OverlayLayoutAxis, _ newValue: OverlayLayoutAxis) {
        if newValue == .vertical {
            frameCoordinator.clearCapturedPinboardLayout()
            dragCoordinator.clearPinboardLayoutState()
        }
    }

    func handleBroadcasterEvent(_ event: ClipboardEvent) {
        if event == .overlayDidShow {
            searchFocused = true
            announceOverlayItemCount()
        }
    }
}

// MARK: - Keyboard Setup

private extension OverlayShellView {
    func installKeyboardHandlers() {
        installReturnKeyHandler()
        installSpaceKeyHandler()
        installEscapeKeyHandler()
    }

    func installReturnKeyHandler() {
        guard let window else { return }
        let handler: () -> Void = { [weak viewModel, weak modifierMonitor] in
            guard let viewModel, let modifierMonitor else { return }
            viewModel.handleReturnKey(
                orderedItems: self.filteredItems,
                isShiftPressed: modifierMonitor.isShiftPressed
            )
        }
        objc_setAssociatedObject(window, &ReturnKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }

    func installSpaceKeyHandler() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { _ in
            if isCreatingPinboard || renamePinboardID != nil || renameItemID != nil {
                return false
            }
            if isSearchExpanded, searchFocused {
                return false
            }
            return previewCoordinator.togglePreviewForItem(
                nil,
                selectedItemIDs: viewModel.selectedItemIDs,
                onSelectionChange: viewModel.restoreSelection,
                filteredItems: filteredItems
            )
        }
        objc_setAssociatedObject(window, &SpaceKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }

    func installEscapeKeyHandler() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { _ in
            if previewCoordinator.isPreviewPopoverPresented {
                previewCoordinator.closePreview()
                return true
            }
            if isCreatingPinboard || renamePinboardID != nil {
                handlePinboardCancel()
                return true
            }
            return false
        }
        objc_setAssociatedObject(window, &EscapeKeyHandlerKey, handler as Any, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Item Action Handlers

private extension OverlayShellView {
    func handleItemPaste(_ item: ClipItem) {
        pasteStackManager.pasteItemOrSelection(
            item: item,
            plainText: false,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }

    func handleItemPastePlainText(_ item: ClipItem) {
        pasteStackManager.pasteItemOrSelection(
            item: item,
            plainText: true,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }

    func handleCopyItem(_ item: ClipItem) {
        actionHandlers.copyItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            filteredItems: filteredItems,
            eventBroadcaster: eventBroadcaster
        )
    }

    func handleDeleteItem(_ item: ClipItem) {
        actionHandlers.deleteItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            onClearSelection: viewModel.clearSelection
        )
    }

    func handleTogglePin(_ item: ClipItem) {
        actionHandlers.togglePin(item, allowPinning: allowPinning)
    }

    func handleOpenEditor(_ item: ClipItem) {
        previewCoordinator.openEditor(for: item, closeOverlay: viewModel.closeOverlayForSettings)
    }

    func handleCommitItemRename(item: ClipItem, newTitle: String) {
        actionHandlers.commitItemRename(item: item, newTitle: newTitle)
        renameItemID = nil
    }

    func handleCardTap(_ item: ClipItem) {
        closeSearchIfEmpty()
        viewModel.selectItem(
            item,
            in: filteredItems,
            isShiftPressed: modifierMonitor.isShiftPressed,
            isCommandPressed: modifierMonitor.isCommandPressed
        )
    }

    func handleCardDoubleTap(_ item: ClipItem) {
        closeSearchIfEmpty()
        viewModel.paste(item: item, plainText: modifierMonitor.isShiftPressed)
    }

    func handleReorderItems(_ draggedIDs: [NSManagedObjectID], _ target: ClipItem, insertBefore: Bool) {
        actionHandlers.reorderItems(
            draggedIDs,
            target,
            insertBefore: insertBefore,
            filteredItems: filteredItems,
            isSearchActive: isSearchActive
        )
    }

    func handlePasteOutside(_ itemIDs: [NSManagedObjectID]) {
        pasteStackManager.pasteOutside(
            itemIDs: itemIDs,
            plainText: modifierMonitor.isShiftPressed,
            orderedItems: filteredItems,
            viewModel: viewModel
        )
    }
}

// MARK: - Pinboard Action Handlers

private extension OverlayShellView {
    func handlePinboardSelect(_ id: UUID?) {
        closeSearchIfEmpty()
        withAnimation(.easeOut(duration: 0.14)) {
            searchModel.selectedPinboardID = id
        }
    }

    func handlePinboardCreateStart() {
        closeSearchIfEmpty()
        renamePinboardColor = nextAvailablePinboardColorHex()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isCreatingPinboard = true
        }
        renamePinboardName = ""
        renamePinboardIcon = nil
    }

    func handleCreatePinboardFromVerticalPicker() {
        closeSearchIfEmpty()
        verticalPinboardDraftName = nextAvailablePinboardName()
        verticalPinboardDraftColor = nextAvailablePinboardColorHex()
        verticalPinboardDraftIcon = nil
        shouldPresentVerticalPinboardStylePicker = false
        isVerticalPinboardCreatePresented = true
    }

    func commitVerticalPinboardCreate() {
        let name = verticalPinboardDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let didCreate = pinboardManager.createPinboard(
            name: name,
            colorHex: verticalPinboardDraftColor,
            iconName: verticalPinboardDraftIcon,
            pendingItem: pendingPinboardItem
        )
        guard didCreate else { return }

        pendingPinboardItem = nil
        isVerticalPinboardCreatePresented = false
        shouldPresentVerticalPinboardStylePicker = false

        DispatchQueue.main.async {
            let createdPinboard = visiblePinboards
                .sorted { $0.sortOrder > $1.sortOrder }
                .first(where: { $0.name == name })
            if let createdPinboard {
                withAnimation(.easeOut(duration: 0.14)) {
                    searchModel.selectedPinboardID = createdPinboard.id
                }
            }
        }
    }

    func cancelVerticalPinboardCreate() {
        isVerticalPinboardCreatePresented = false
        shouldPresentVerticalPinboardStylePicker = false
        pendingPinboardItem = nil
    }

    func presentVerticalPinboardEdit() {
        guard let selectedCustomPinboard else { return }
        verticalPinboardEditDraftName = selectedCustomPinboard.name
        verticalPinboardEditDraftColor = selectedCustomPinboard.colorHex
        verticalPinboardEditDraftIcon = selectedCustomPinboard.iconName
        shouldPresentVerticalPinboardEditStylePicker = false
        isVerticalPinboardEditPresented = true
    }

    func commitVerticalPinboardEdit() {
        guard let selectedCustomPinboard else { return }
        let name = verticalPinboardEditDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let didSave = pinboardManager.renamePinboard(
            objectID: selectedCustomPinboard.objectID,
            name: name,
            colorHex: verticalPinboardEditDraftColor,
            iconName: verticalPinboardEditDraftIcon
        )
        guard didSave else { return }

        isVerticalPinboardEditPresented = false
        shouldPresentVerticalPinboardEditStylePicker = false
    }

    func cancelVerticalPinboardEdit() {
        isVerticalPinboardEditPresented = false
        shouldPresentVerticalPinboardEditStylePicker = false
    }

    func handleSetPinboardLock(_ pinboard: Pinboard, _ isEnabled: Bool) {
        lockHandler.setPinboardLock(pinboard, enabled: isEnabled)
    }

    func handleRequestPinboardUnlock(_ pinboard: Pinboard) {
        lockHandler.requestPinboardUnlock(pinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func handleLockPinboardNow(_ pinboard: Pinboard) {
        lockHandler.lockPinboardNow(pinboard, selectedPinboardID: searchModel.selectedPinboardID)
    }

    func handlePinboardRenameStart(_ pinboard: Pinboard) {
        renamePinboardID = pinboard.objectID
        renamePinboardName = pinboard.name
        renamePinboardColor = pinboard.colorHex
        renamePinboardIcon = pinboard.iconName
    }

    func handleDeletePinboard(_ pinboard: Pinboard) {
        searchModel.selectedPinboardID = actionHandlers.deletePinboard(
            pinboard,
            selectedPinboardID: searchModel.selectedPinboardID
        )
    }

    func handlePinboardReorder(_ dragged: Pinboard, _ target: Pinboard, insertBefore: Bool) {
        pinboardManager.optimisticReorderPinboards(
            dragged: dragged,
            target: target,
            insertBefore: insertBefore,
            visiblePinboards: visiblePinboards
        )
    }

    func handlePinboardMoveItem(_ pinboard: Pinboard, _ itemURIString: String) {
        guard pinboardLockController.canAccess(pinboardID: pinboard.id) else { return }
        pinboardManager.moveItemToPinboard(pinboard, itemURIString: itemURIString)
    }

    func handlePinboardCommit() {
        if isCreatingPinboard {
            let didCreate = actionHandlers.commitPinboardCreate(
                name: renamePinboardName,
                colorHex: renamePinboardColor,
                iconName: renamePinboardIcon,
                pendingItem: pendingPinboardItem
            )
            guard didCreate else { return }

            pendingPinboardItem = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isCreatingPinboard = false
            }
            renamePinboardIcon = nil
        } else if let objectID = renamePinboardID {
            let didRename = actionHandlers.commitPinboardRename(
                objectID: objectID,
                name: renamePinboardName,
                colorHex: renamePinboardColor,
                iconName: renamePinboardIcon
            )
            guard didRename else { return }

            renamePinboardID = nil
            renamePinboardIcon = nil
        }
    }

    func handlePinboardCancel() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isCreatingPinboard = false
        }
        renamePinboardID = nil
        renamePinboardIcon = nil
    }

    func handlePinboardLayoutChange(_ layout: PinboardLayoutInfo) {
        DispatchQueue.main.async {
            frameCoordinator.updateCapturedPinboardLayout(layout)
            dragCoordinator.updatePinboardLayout(layout)
        }
    }

    func handleMoveToPinboard(_ item: ClipItem, _ pinboard: Pinboard) {
        if !pinboardLockController.canAccess(pinboardID: pinboard.id) {
            handleRequestPinboardUnlock(pinboard)
            return
        }

        // If the clicked item is part of a multi-selection, move all selected items
        let selectedIDs = viewModel.selectedItemIDs
        if selectedIDs.count > 1, selectedIDs.contains(item.objectID) {
            // Get all selected items from filteredItems
            let selectedItems = filteredItems.filter { selectedIDs.contains($0.objectID) }
            for selectedItem in selectedItems {
                actionHandlers.handleMoveToPinboard(selectedItem, pinboard)
            }
        } else {
            // Single item or clicked item not in selection
            actionHandlers.handleMoveToPinboard(item, pinboard)
        }
    }

    func beginPinboardCreate(for item: ClipItem?) {
        pendingPinboardItem = item
        if overlayLayoutAxis == .vertical {
            handleCreatePinboardFromVerticalPicker()
        } else {
            renamePinboardColor = nextAvailablePinboardColorHex()
            renamePinboardName = ""
            renamePinboardIcon = nil
            isCreatingPinboard = true
        }
    }
}

// MARK: - Drag & Drop Handlers

private extension OverlayShellView {
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

// MARK: - Search Handlers

private extension OverlayShellView {
    func handleSearchButtonTap() {
        if isSearchExpanded {
            if !isFilterPopoverPresented {
                searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
            }
            isFilterPopoverPresented.toggle()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSearchExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }

    func handleSearchClear() {
        isFilterPopoverPresented = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSearchExpanded = false
            searchModel.searchText = ""
            searchFocused = false
        }
    }

    func closeSearchIfEmpty() {
        guard isSearchExpanded,
            searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        isFilterPopoverPresented = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            isSearchExpanded = false
            searchFocused = false
        }
    }
}

// MARK: - Helper Methods

private extension OverlayShellView {
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
        Array(items).filter { !lockHandler.isItemVisible($0, selectedPinboardID: nil) == false }
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
        let announcement = "Paste, \(filteredItems.count) items"
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
            previewCoordinator.closeAllMenus()
            return
        }

        if isSearchExpanded,
            let searchFieldFrame = dragCoordinator.searchFieldFrame,
            !searchFieldFrame.contains(location)
        {
            closeSearchIfEmpty()
        }

        guard isCreatingPinboard || renamePinboardID != nil,
            let pinboardEditorFrame = dragCoordinator.pinboardEditorFrame,
            !pinboardEditorFrame.contains(location)
        else { return }

        if isCreatingPinboard && renamePinboardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handlePinboardCancel()
        } else {
            handlePinboardCommit()
        }
    }
}
