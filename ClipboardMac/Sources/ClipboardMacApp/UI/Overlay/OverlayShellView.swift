import AppKit
import ClipboardCore
import ClipboardMacServices
import OSLog
import SwiftUI

struct OverlayShellView: View {
    private let itemEditorWindowController: ItemEditorWindowController
    private let clipItemEditor: any ClipItemEditing

    @EnvironmentObject var viewModel: OverlayViewModel
    @Environment(\.clipboardEventBroadcaster) var eventBroadcaster
    @State var renamePinboardID: NSManagedObjectID?
    @State var renamePinboardName = ""
    @State var renamePinboardColor = PinboardPalette.defaultHex
    @State var isCreatingPinboard = false
    @State var pendingPinboardItem: ClipItem?
    @State var renameItemID: NSManagedObjectID?
    @FocusState var searchFocused: Bool
    @StateObject var modifierMonitor = ModifierKeyMonitor()
    @StateObject var searchModel: OverlaySearchViewModel
    @StateObject var frameCoordinator = FrameCoordinator()
    @StateObject var dragCoordinator = DragCoordinator()
    @StateObject var pinboardLockController = PinboardLockController()
    @State var window: NSWindow?
    @State var isSearchExpanded = false
    @State var isFilterPopoverPresented = false

    @State var previewItemID: NSManagedObjectID?
    @State var isPreviewPopoverPresented = false

    private let itemOperationsHandler: ItemOperationsHandler
    private let pinboardManager: PinboardManager
    private let pasteStackManager = PasteStackManager()
    private let overlayCoordinateSpaceName = "OverlaySpace"
    private let headerButtonSize: CGFloat = 30
    private let headerButtonIconSize: CGFloat = 14
    private let searchCollapsedWidth: CGFloat = 30
    private let searchExpandedWidth: CGFloat = 220
    private var headerSideWidth: CGFloat { searchExpandedWidth + 20 }

    init(persistence: PersistenceController, store: ClipItemStore) {
        self.itemEditorWindowController = ItemEditorWindowController(clipItemEditor: store)
        self.clipItemEditor = store
        self.itemOperationsHandler = ItemOperationsHandler(store: store)
        self.pinboardManager = PinboardManager(store: store, persistence: persistence)
        _searchModel = StateObject(wrappedValue: OverlaySearchViewModel(store: store))
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
    }

    private var mainContent: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                // Header Bar
                ZStack(alignment: .center) {
                    // Center: Pinboards
                    PinboardTabBar(
                        pinboards: visiblePinboards,
                        selectedID: searchModel.selectedPinboardID,
                        isLocked: { pinboardLockController.isLocked(pinboardID: $0.id) },
                        isUnlocked: { pinboardLockController.canAccess(pinboardID: $0.id) },
                        editingID: $renamePinboardID,
                        isCreating: $isCreatingPinboard,
                        draftName: $renamePinboardName,
                        draftColor: $renamePinboardColor,
                        isGlobalDragActive: dragCoordinator.dragPreviewData != nil,
                        window: window,
                        onPreviewUpdate: { data in
                            dragCoordinator.updatePinboardDragPreviewWindow(
                                data, parentWindow: window)
                        },
                        onSelect: { id in
                            closeSearchIfEmpty()
                            withAnimation(.easeOut(duration: 0.14)) {
                                searchModel.selectedPinboardID = id
                            }
                        },
                        onCreate: {
                            closeSearchIfEmpty()
                            // Smart Color Selection
                            let usedColors = Set(pinboards.map { $0.colorHex })
                            let availableColors = PinboardPalette.colors.filter {
                                !usedColors.contains($0)
                            }
                            renamePinboardColor =
                                availableColors.first ?? PinboardPalette.colors.randomElement()
                                ?? PinboardPalette.defaultHex

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                isCreatingPinboard = true
                            }
                            renamePinboardName = ""
                        },
                        onSetLockEnabled: { pinboard, isEnabled in
                            setPinboardLock(pinboard, enabled: isEnabled)
                        },
                        onUnlock: requestPinboardUnlock,
                        onLockNow: lockPinboardNow,
                        onRename: { pinboard in
                            renamePinboardID = pinboard.objectID
                            renamePinboardName = pinboard.name
                            renamePinboardColor = pinboard.colorHex
                        },
                        onColorChange: pinboardManager.changePinboardColor,
                        onDelete: deletePinboard,
                        onReorder: { dragged, target, insertBefore in
                            pinboardManager.optimisticReorderPinboards(
                                dragged: dragged,
                                target: target,
                                insertBefore: insertBefore,
                                visiblePinboards: visiblePinboards
                            )
                        },
                        onReorderEnd: pinboardManager.saveChanges,
                        onMoveItem: { pinboard, itemURIString in
                            guard pinboardLockController.canAccess(pinboardID: pinboard.id) else {
                                return
                            }
                            pinboardManager.moveItemToPinboard(
                                pinboard, itemURIString: itemURIString)
                        },
                        onCommit: {
                            if isCreatingPinboard {
                                commitPinboardCreate()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    isCreatingPinboard = false
                                }
                            } else if renamePinboardID != nil {
                                commitPinboardRename()
                                renamePinboardID = nil
                            }
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                isCreatingPinboard = false
                            }
                            renamePinboardID = nil
                        },
                        coordinateSpaceName: overlayCoordinateSpaceName
                    )
                    .padding(.horizontal, headerSideWidth)
                    .frame(height: headerButtonSize, alignment: .center)
                    .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
                        DispatchQueue.main.async {
                            frameCoordinator.updateCapturedPinboardLayout(layout)
                            dragCoordinator.updatePinboardLayout(layout)
                        }
                    }
                    .onPreferenceChange(SearchFieldFrameKey.self) { frame in
                        DispatchQueue.main.async {
                            dragCoordinator.updateSearchFieldFrame(frame)
                        }
                    }

                    // Left: Search
                    HStack(alignment: .center) {
                        HStack(spacing: 0) {
                            // Search Icon / Toggle
                            Button(action: handleSearchButtonTap) {
                                searchIcon
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("overlay.search.toggle")
                            .accessibilityLabel(searchButtonAccessibilityLabel)
                            .accessibilityValue(searchButtonAccessibilityValue)
                            .accessibilityHint(searchButtonAccessibilityHint)

                            if isSearchExpanded {
                                HStack(spacing: 6) {
                                    TextField("Search", text: $searchModel.searchText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .tint(.white)
                                        .focused($searchFocused)
                                        .frame(height: headerButtonSize)
                                        .accessibilityIdentifier("overlay.search.field")
                                        .accessibilityLabel("Search")
                                        .accessibilityValue(searchFieldAccessibilityValue)
                                        .accessibilityHint("Type to filter items")

                                    // Close search button (on the right)
                                    Button(action: {
                                        isFilterPopoverPresented = false
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8))
                                        {
                                            isSearchExpanded = false
                                            searchModel.searchText = ""
                                            searchFocused = false
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(3)
                                            .background(
                                                Color.white.opacity(
                                                    DesignTokens.Opacity.backgroundMedium)
                                            )
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Circle())
                                    .accessibilityIdentifier("overlay.search.clear")
                                    .accessibilityLabel("Clear search")
                                    .accessibilityHint(
                                        "Clears search text and collapses search field")
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 6)
                            }
                        }
                        .background(
                            Group {
                                if #available(macOS 26.0, *) {
                                    Capsule()
                                        .fill(Color.clear)
                                        .glassNavigationStyle()
                                        .opacity(isSearchExpanded ? 1 : 0)
                                } else {
                                    Capsule()
                                        .fill(
                                            Color.white.opacity(
                                                DesignTokens.Opacity.backgroundMedium)
                                        )
                                        .opacity(isSearchExpanded ? 1 : 0)
                                }
                            }
                        )
                        .overlay(
                            Group {
                                if #available(macOS 26.0, *) {
                                    // Glass effect handles its own border
                                    EmptyView()
                                } else {
                                    Capsule()
                                        .stroke(
                                            Color.white.opacity(
                                                isSearchExpanded
                                                    ? DesignTokens.Opacity.borderStrong : 0),
                                            lineWidth: 1
                                        )
                                }
                            }
                        )
                        .frame(
                            width: isSearchExpanded ? searchExpandedWidth : searchCollapsedWidth,
                            height: headerButtonSize,
                            alignment: .leading
                        )
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.8), value: isSearchExpanded
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SearchFieldFrameKey.self,
                                    value: proxy.frame(in: .named(overlayCoordinateSpaceName))
                                )
                            }
                        )
                        .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .bottom) {
                            searchFilterPopover
                        }
                    }
                    .frame(width: headerSideWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)  // Adjust padding

                    // Right: Settings
                    HStack {
                        Spacer()
                        Group {
                            if #available(macOS 14.0, *) {
                                OverlaySettingsButton14(
                                    closeOverlay: { completion in
                                        viewModel.closeOverlayForSettings(completion: completion)
                                    },
                                    label: AnyView(settingsIcon)
                                )
                            } else {
                                Button {
                                    viewModel.closeOverlayForSettings {
                                        openSettingsLegacy()
                                    }
                                } label: {
                                    settingsIcon
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("overlay.settings")
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Opens settings")
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 14)
                .frame(height: headerButtonSize)
                .zIndex(1)

                ZStack(alignment: .topLeading) {
                    if isSelectedPinboardAwaitingUnlock {
                        lockedPinboardView
                            .padding(.horizontal, 14)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else if filteredItems.isEmpty {
                        emptyStateView
                            .padding(.horizontal, 14)
                            .transition(.opacity)
                    } else {
                        ItemCardRow(
                            items: filteredItems,
                            pinboards: movablePinboards,
                            mode: viewModel.mode,
                            selectedItemIDs: viewModel.selectedItemIDs,
                            editingItemID: renameItemID,
                            allowPinning: allowPinning,
                            clipItemEditor: clipItemEditor,
                            isDragEnabled: isDragEnabled,
                            isReorderingEnabled: isReorderingEnabled,
                            onPaste: { item in
                                pasteStackManager.pasteItemOrSelection(
                                    item: item,
                                    plainText: false,
                                    selectedItemIDs: viewModel.selectedItemIDs,
                                    orderedItems: filteredItems,
                                    viewModel: viewModel
                                )
                            },
                            onPastePlainText: { item in
                                pasteStackManager.pasteItemOrSelection(
                                    item: item,
                                    plainText: true,
                                    selectedItemIDs: viewModel.selectedItemIDs,
                                    orderedItems: filteredItems,
                                    viewModel: viewModel
                                )
                            },
                            onCopy: copyItem,
                            onDelete: deleteItem,
                            onTogglePin: togglePin,
                            onMoveToPinboard: handleMoveToPinboard,
                            onCreatePinboard: { beginPinboardCreate(for: $0) },
                            onEdit: { openEditor(for: $0) },
                            onRename: renameItem,
                            onCommitRename: { item, newTitle in
                                commitItemRename(item: item, newTitle: newTitle)
                            },
                            onTap: handleCardTap,
                            onDoubleTap: handleCardDoubleTap,
                            onReorder: reorderItems,
                            onReorderEnd: pinboardManager.saveChanges,
                            onDropToPinboard: handleDropToPinboard,
                            onDropToAll: handleDropToAll,
                            onPasteOutside: { itemIDs in
                                pasteStackManager.pasteOutside(
                                    itemIDs: itemIDs,
                                    plainText: modifierMonitor.isShiftPressed,
                                    orderedItems: filteredItems,
                                    viewModel: viewModel
                                )
                            },
                            coordinateSpaceName: overlayCoordinateSpaceName,
                            pinboardFrames: dragCoordinator.pinboardFrames,
                            allPinboardFrame: dragCoordinator.allPinboardFrame,
                            window: window,
                            dragPreviewData: $dragCoordinator.dragPreviewData,
                            onPreviewUpdate: { data in
                                dragCoordinator.updateDragPreviewWindow(data, parentWindow: window)
                            },
                            previewItemID: $previewItemID,
                            isPreviewPopoverPresented: $isPreviewPopoverPresented
                        )
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isSelectedPinboardAwaitingUnlock)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(pinboardSelectionKey)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.14), value: pinboardSelectionKey)

                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Resize Handle Area
            ResizeHandleView(window: window)
        }
        .coordinateSpace(name: overlayCoordinateSpaceName)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .named(overlayCoordinateSpaceName)) { location in
            handleOverlayTap(at: location)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(overlayCoordinateSpaceName))
                .onEnded { value in
                    handleOverlayTap(at: value.location)
                }
        )
        .background(WindowAccessor(window: $window))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onChange(of: dragCoordinator.dragPreviewData) { newData, _ in
            dragCoordinator.updateDragPreviewWindow(newData, parentWindow: window)
        }
        .alert("Accessibility Permission Required", isPresented: $viewModel.showAccessibilityAlert)
        {
            Button("Open System Settings") {
                viewModel.requestAccessibility()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste needs Accessibility permission to paste into other apps.")
        }
        .onChange(of: searchModel.selectedPinboardID) {
            if isSelectedPinboardAwaitingUnlock {
                viewModel.clearSelection()
                closePreview()
            }
            if isFilterPopoverPresented {
                searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
            }
        }
        .onChange(of: selectedPinboardIsAccessible) { isAccessible, _ in
            if !isAccessible, searchModel.selectedPinboardID != nil {
                viewModel.clearSelection()
                closePreview()
            }
        }
        .onChange(of: isSearchExpanded) { expanded, _ in
            if !expanded {
                isFilterPopoverPresented = false
            }
        }
        .onChange(of: searchFocused) { focused, _ in
            // Don't auto-close search on focus lost - let user close it explicitly
        }
        .onChange(of: keyHandlerRefreshToken) { _, _ in
            installSpaceKeyHandlerIfPossible()
            installEscapeKeyHandlerIfPossible()
        }
        .onAppear {
            searchFocused = true
            modifierMonitor.start()
            pinboardLockController.reconcile(validPinboardIDs: visiblePinboardIDs)
            ensureValidSelection()
            dragCoordinator.ensurePreviewWindow()
            dragCoordinator.ensurePinboardPreviewWindow()
            installReturnKeyHandlerIfPossible()
            installSpaceKeyHandlerIfPossible()
            installEscapeKeyHandlerIfPossible()
        }
        .onChange(of: window) { _, _ in
            installReturnKeyHandlerIfPossible()
            installSpaceKeyHandlerIfPossible()
            installEscapeKeyHandlerIfPossible()
        }
        .onDisappear {
            modifierMonitor.stop()
            dragCoordinator.cleanupPreviewWindow()
            dragCoordinator.cleanupPinboardPreviewWindow()

            previewItemID = nil
            isPreviewPopoverPresented = false

            // Close search on overlay close only if empty
            if searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchExpanded = false
                searchFocused = false
            }
            isFilterPopoverPresented = false

            // Allow clean state for next time
            isCreatingPinboard = false
            renamePinboardID = nil
        }
        .onChange(of: visiblePinboardIDs) {
            pinboardLockController.reconcile(validPinboardIDs: visiblePinboardIDs)
            ensureValidSelection()
        }
        .onChange(of: itemsSourceAppsHash) {
            if isFilterPopoverPresented {
                searchModel.updateAppOptions(
                    from: allItemsVisibleInAllPinboard)
            }
        }
        .onReceive(eventBroadcaster.events) { event in
            if event == .overlayDidShow {
                searchFocused = true
                announceOverlayItemCount()
            }
        }
        .onChange(of: viewModel.selectedItemIDs) { _, _ in
            if isPreviewPopoverPresented {
                closePreview()
            }
        }
        .environmentObject(frameCoordinator)
    }

    private var emptyStateView: some View {
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
        if searchModel.selectedPinboardID != nil {
            return "square.stack.3d.up.slash"
        }
        return "clipboard"
    }

    private var emptyStateTitle: String {
        if isSearchActive {
            return "No matches"
        }
        if searchModel.selectedPinboardID != nil {
            return "Pinboard is empty"
        }
        return "All items are empty"
    }

    private var emptyStateText: String {
        if isSearchActive {
            if searchModel.isSearchTextActive {
                return "No results for \"\(searchModel.searchText)\". Try another keyword."
            }
            return "No results for the current filters."
        }
        if searchModel.selectedPinboardID != nil {
            return "No items in this pinboard"
        }
        return "Copy something to get started."
    }

    private var lockedPinboardView: some View {
        VStack(spacing: 14) {
            Image(
                systemName: pinboardLockController.isAuthenticating ? "lock.open.fill" : "lock.fill"
            )
            .font(.system(size: 32, weight: .light))
            .foregroundStyle(.tertiary)
            .contentTransition(.symbolEffect(.replace))

            Text(lockedPinboardTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                guard let selectedCustomPinboard else { return }
                requestPinboardUnlock(selectedCustomPinboard)
            } label: {
                if pinboardLockController.isAuthenticating {
                    ProgressView("Authenticating...")
                } else {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pinboardLockController.isAuthenticating || selectedCustomPinboard == nil)
            .accessibilityIdentifier("overlay.pinboard.unlock")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var lockedPinboardTitle: String {
        guard let selectedCustomPinboard else { return "Pinboard is locked" }
        return "\"\(selectedCustomPinboard.name)\" is locked"
    }

    private var allItemsVisibleInAllPinboard: [ClipItem] {
        Array(items).filter { !isItemHiddenInAllPinboard($0) }
    }

    func isItemVisible(_ item: ClipItem, selectedPinboardID: UUID?) -> Bool {
        if let selectedPinboardID {
            guard item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false else {
                return false
            }
            return selectedPinboardIsAccessible
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

    private func setPinboardLock(_ pinboard: Pinboard, enabled: Bool) {
        if !enabled && !pinboardLockController.canAccess(pinboardID: pinboard.id) {
            requestPinboardUnlock(pinboard)
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            pinboardLockController.setLockEnabled(enabled, pinboardID: pinboard.id)
        }
        if enabled && searchModel.selectedPinboardID == pinboard.id {
            viewModel.clearSelection()
            closePreview()
        }
    }

    private func lockPinboardNow(_ pinboard: Pinboard) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pinboardLockController.lockNow(pinboardID: pinboard.id)
        }
        if searchModel.selectedPinboardID == pinboard.id {
            viewModel.clearSelection()
            closePreview()
        }
    }

    private func requestPinboardUnlock(_ pinboard: Pinboard) {
        Task { @MainActor in
            let unlocked = await pinboardLockController.unlock(
                pinboardID: pinboard.id,
                pinboardName: pinboard.name
            )
            if unlocked, searchModel.selectedPinboardID == pinboard.id {
                viewModel.clearSelection()
            }
        }
    }

    private func handleMoveToPinboard(_ item: ClipItem, _ pinboard: Pinboard) {
        guard pinboardLockController.canAccess(pinboardID: pinboard.id) else { return }
        pinboardManager.toggleItem(item, in: pinboard)
    }

    private func copyItem(_ item: ClipItem) {
        itemOperationsHandler.copyItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: filteredItems,
            eventBroadcaster: eventBroadcaster
        )
    }

    private func installReturnKeyHandlerIfPossible() {
        guard let window else { return }
        let handler: () -> Void = { [weak viewModel, weak modifierMonitor] in
            guard let viewModel, let modifierMonitor else { return }
            viewModel.handleReturnKey(
                orderedItems: self.filteredItems,
                isShiftPressed: modifierMonitor.isShiftPressed
            )
        }
        objc_setAssociatedObject(
            window,
            &ReturnKeyHandlerKey,
            handler as Any,
            .OBJC_ASSOCIATION_RETAIN
        )
    }

    private func installSpaceKeyHandlerIfPossible() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { _ in
            if isCreatingPinboard || renamePinboardID != nil || renameItemID != nil {
                return false
            }
            if isSearchExpanded, searchFocused {
                return false
            }
            return togglePreviewForCurrentSelection()
        }
        objc_setAssociatedObject(
            window,
            &SpaceKeyHandlerKey,
            handler as Any,
            .OBJC_ASSOCIATION_RETAIN
        )
    }

    private func installEscapeKeyHandlerIfPossible() {
        guard let window else { return }
        let handler: (NSEvent) -> Bool = { _ in
            if isPreviewPopoverPresented {
                closePreview()
                return true
            }
            return false
        }
        objc_setAssociatedObject(
            window,
            &EscapeKeyHandlerKey,
            handler as Any,
            .OBJC_ASSOCIATION_RETAIN
        )
    }

    private func closeOverlayMenus() {
        previewItemID = nil
        isPreviewPopoverPresented = false
    }

    @discardableResult
    private func togglePreviewForCurrentSelection() -> Bool {
        let selected =
            filteredItems.first(where: { viewModel.selectedItemIDs.contains($0.objectID) })
            ?? filteredItems.first
        guard let selected else {
            closePreview()
            return false
        }
        if !viewModel.selectedItemIDs.contains(selected.objectID) {
            viewModel.restoreSelection([selected.objectID], in: filteredItems)
        }
        if isPreviewPopoverPresented, previewItemID == selected.objectID {
            closePreview()
            return true
        }
        previewItemID = selected.objectID
        isPreviewPopoverPresented = true
        return true
    }

    private func openEditor(for item: ClipItem) {
        closePreview()

        // Close the overlay first
        viewModel.closeOverlayForSettings { [itemEditorWindowController] in
            // Then show the editor window
            itemEditorWindowController.show(
                item: item,
                onSave: { _ in },
                onClose: {
                    // Optional: reopen overlay or do nothing
                }
            )
        }
    }

    private func closeEditor() {
        itemEditorWindowController.hide()
    }

    private func closePreview() {
        previewItemID = nil
        isPreviewPopoverPresented = false
    }

    private func overlayAnchorFrame(for itemID: NSManagedObjectID) -> CGRect? {
        guard let localFrame = frameCoordinator.latestItemFrames[itemID] else { return nil }
        let rowFrame = frameCoordinator.latestItemRowFrame
        return CGRect(
            x: localFrame.minX + rowFrame.minX,
            y: localFrame.minY + rowFrame.minY,
            width: localFrame.width,
            height: localFrame.height
        )
    }

    private var previewItem: ClipItem? {
        guard let id = previewItemID else { return nil }
        return filteredItems.first(where: { $0.objectID == id })
    }

    private func deleteItem(_ item: ClipItem) {
        itemOperationsHandler.deleteItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            onClearSelection: viewModel.clearSelection
        )
    }

    private func renameItem(_ item: ClipItem) {
        renameItemID = item.objectID
    }

    private func commitItemRename(item: ClipItem, newTitle: String) {
        itemOperationsHandler.commitItemRename(itemID: item.objectID, newTitle: newTitle)
        renameItemID = nil
    }

    private func togglePin(_ item: ClipItem) {
        itemOperationsHandler.togglePin(item, allowPinning: allowPinning)
    }

    private func deletePinboard(_ pinboard: Pinboard) {
        searchModel.selectedPinboardID = pinboardManager.deletePinboard(
            pinboard,
            selectedPinboardID: searchModel.selectedPinboardID
        )
        pinboardLockController.setLockEnabled(false, pinboardID: pinboard.id)
    }

    private func commitPinboardRename() {
        guard let objectID = renamePinboardID else { return }
        let trimmedName = renamePinboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        pinboardManager.renamePinboard(
            objectID: objectID, name: trimmedName, colorHex: renamePinboardColor)
    }

    private func commitPinboardCreate() {
        let trimmedName = renamePinboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if pinboardManager.createPinboard(
            name: trimmedName,
            colorHex: renamePinboardColor,
            pendingItem: pendingPinboardItem
        ) {
            pendingPinboardItem = nil
        }
    }

    private var searchButtonAccessibilityLabel: String {
        isSearchExpanded ? "Search filters" : "Search"
    }

    private var searchButtonAccessibilityValue: String {
        var parts: [String] = []
        parts.append(isSearchExpanded ? "Expanded" : "Collapsed")
        if searchModel.hasActiveFilters {
            parts.append("Filters active")
        }
        return parts.joined(separator: ", ")
    }

    private var searchButtonAccessibilityHint: String {
        if isSearchExpanded {
            return isFilterPopoverPresented ? "Hide search filters" : "Show search filters"
        }
        return "Expand search field"
    }

    private var searchFieldAccessibilityValue: String {
        let trimmed = searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty" : trimmed
    }

    private var searchIcon: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .frame(width: headerButtonSize, height: headerButtonSize)
                    .glassCircleButton()
                    .opacity(isSearchExpanded ? 0 : 1)
            } else {
                Circle()
                    .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
                    .frame(width: headerButtonSize, height: headerButtonSize)
                    .opacity(isSearchExpanded ? 0 : 1)
            }

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)

            if searchModel.hasActiveFilters {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .offset(x: 9, y: -9)
            }
        }
        .frame(width: headerButtonSize, height: headerButtonSize)
        .contentShape(Rectangle())
    }

    private var searchFilterPopover: some View {
        FilterPopoverView(
            dateFilter: $searchModel.dateFilter,
            typeFilters: $searchModel.typeFilters,
            appFilters: $searchModel.appFilters,
            appOptions: searchModel.appOptions,
            onClear: searchModel.clearFilters
        )
    }

    private func announceOverlayItemCount() {
        let announcement = "Paste, \(filteredItems.count) items"
        let element: Any
        if let window {
            element = window
        } else {
            element = NSApp ?? NSApplication.shared
        }
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement]
        )
    }

    private func handleSearchButtonTap() {
        if isSearchExpanded {
            if !isFilterPopoverPresented {
                searchModel.updateAppOptions(from: allItemsVisibleInAllPinboard)
            }
            isFilterPopoverPresented.toggle()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSearchExpanded = true
            }
            // Delay focus until the TextField is rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }

    private func ensureValidSelection() {
        guard let selectedPinboardID = searchModel.selectedPinboardID else { return }
        guard visiblePinboards.contains(where: { $0.id == selectedPinboardID }) else {
            searchModel.selectedPinboardID = nil
            return
        }
    }

    private func beginPinboardCreate(for item: ClipItem?) {
        pendingPinboardItem = item

        let usedColors = Set(pinboards.map { $0.colorHex })
        let availableColors = PinboardPalette.colors.filter { !usedColors.contains($0) }
        renamePinboardColor =
            availableColors.first ?? PinboardPalette.colors.randomElement()
            ?? PinboardPalette.defaultHex

        renamePinboardName = ""
        isCreatingPinboard = true
    }

    func sortItems(_ items: [ClipItem]) -> [ClipItem] {
        guard searchModel.selectedPinboardID != nil else {
            return items.sorted { lhs, rhs in
                if lhs.displayOrder != rhs.displayOrder {
                    return lhs.displayOrder > rhs.displayOrder
                }
                return lhs.createdAt > rhs.createdAt
            }
        }

        return items.sorted { lhs, rhs in
            if allowPinning, lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder > rhs.displayOrder
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func reorderItems(
        _ draggedIDs: [NSManagedObjectID], _ target: ClipItem, insertBefore: Bool
    ) {
        guard !isSearchActive else { return }

        var ordered = filteredItems

        // Extract dragged items in their current order
        let draggedItems = draggedIDs.compactMap { id in
            ordered.first { $0.objectID == id }
        }

        // Remove all dragged items
        ordered.removeAll { item in
            draggedIDs.contains(item.objectID)
        }

        // Find target index in the new array (after removal)
        guard var targetIndex = ordered.firstIndex(where: { $0.objectID == target.objectID }) else {
            return
        }

        // Adjust for insertBefore
        if !insertBefore {
            targetIndex += 1
        }

        // Insert dragged items as contiguous group
        ordered.insert(contentsOf: draggedItems, at: targetIndex)

        // Update display orders in View Context (Optimistic UI)
        let now = Date()
        let baseOrder = Int64(now.timeIntervalSince1970 * 1000) + Int64(ordered.count)

        for (index, item) in ordered.enumerated() {
            item.displayOrder = baseOrder - Int64(index)
        }
    }

    private func handleDropToPinboard(_ item: ClipItem, _ pinboardID: NSManagedObjectID) {
        guard let targetPinboard = pinboards.first(where: { $0.objectID == pinboardID }) else {
            return
        }
        guard pinboardLockController.canAccess(pinboardID: targetPinboard.id) else {
            return
        }

        if pinboardManager.handleDropToPinboard(item: item, pinboardID: pinboardID) {
            viewModel.clearSelection()
            // Update search results if search is active to reflect the change
            if searchModel.isSearchTextActive {
                searchModel.refreshSearchNow()
            }
        }
    }

    private func handleDropToAll(_ item: ClipItem) {
        let selectedPinboard = searchModel.selectedPinboardID.flatMap { id in
            pinboards.first(where: { $0.id == id })
        }
        if pinboardManager.handleDropToAll(item: item, selectedPinboard: selectedPinboard) {
            viewModel.clearSelection()
        }
    }

    private func handleCardTap(_ item: ClipItem) {
        closeSearchIfEmpty()
        viewModel.selectItem(
            item,
            in: filteredItems,
            isShiftPressed: modifierMonitor.isShiftPressed,
            isCommandPressed: modifierMonitor.isCommandPressed
        )
    }

    private func handleCardDoubleTap(_ item: ClipItem) {
        closeSearchIfEmpty()
        viewModel.paste(item: item, plainText: modifierMonitor.isShiftPressed)
    }

    /// Closes search only if it's expanded AND the search text is empty
    private func closeSearchIfEmpty() {
        guard isSearchExpanded,
            searchModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        isFilterPopoverPresented = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            isSearchExpanded = false
            searchFocused = false
        }
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
                .background(
                    Circle()
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
                )
                .contentShape(Circle())
        }
    }

    private func openSettingsLegacy() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func handleOverlayTap(at location: CGPoint) {
        if isPreviewPopoverPresented {
            closeOverlayMenus()
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

        if isCreatingPinboard {
            commitPinboardCreate()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isCreatingPinboard = false
            }
        } else if renamePinboardID != nil {
            commitPinboardRename()
            renamePinboardID = nil
        }
    }

}
