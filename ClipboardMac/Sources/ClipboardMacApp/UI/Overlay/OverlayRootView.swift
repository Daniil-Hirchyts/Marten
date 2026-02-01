import AppKit
import ClipboardCore
import ClipboardMacServices
import OSLog
import SwiftUI

struct OverlayRootView: View {
    @EnvironmentObject private var viewModel: OverlayViewModel
    @Environment(\.clipboardEventBroadcaster) private var eventBroadcaster
    @State private var renamePinboardID: NSManagedObjectID?
    @State private var renamePinboardName = ""
    @State private var renamePinboardColor = PinboardPalette.defaultHex
    @State private var isCreatingPinboard = false
    @State private var pendingPinboardItem: ClipItem?
    @State private var renameItemID: NSManagedObjectID?
    @FocusState private var searchFocused: Bool
    @StateObject private var modifierMonitor = ModifierKeyMonitor()
    @StateObject private var searchModel = OverlaySearchViewModel()
    @StateObject private var frameCoordinator = FrameCoordinator()
    @StateObject private var dragCoordinator = DragCoordinator()
    @State private var window: NSWindow?
    @State private var isSearchExpanded = false
    @State private var isFilterPopoverPresented = false

    private let itemOperationsHandler = ItemOperationsHandler()
    private let pinboardManager = PinboardManager()
    private let pasteStackManager = PasteStackManager()
    private let overlayCoordinateSpaceName = "OverlaySpace"
    private let headerButtonSize: CGFloat = 30
    private let headerButtonIconSize: CGFloat = 14
    private let searchCollapsedWidth: CGFloat = 30
    private let searchExpandedWidth: CGFloat = 220
    private var headerSideWidth: CGFloat { searchExpandedWidth + 20 }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "displayOrder", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ],
        predicate: NSPredicate(format: "isTransient == NO"),
        animation: .default
    )
    private var items: FetchedResults<ClipItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)],
        animation: .default
    )
    private var pinboards: FetchedResults<Pinboard>

    private var filteredItems: [ClipItem] {
        let selectedPinboardID = searchModel.selectedPinboardID
        let baseItems = items.filter { item in
            guard let selectedPinboardID else { return true }
            return item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false
        }
        let baseList = searchModel.isSearchTextActive ? searchModel.searchResults : Array(baseItems)
        let filtered = searchModel.applyFilters(to: baseList)
        return sortItems(filtered)
    }

    private var isSearchActive: Bool {
        searchModel.isSearchActive
    }

    private var visiblePinboards: [Pinboard] {
        pinboards.filter { !$0.isSystemClipboard }
    }

    private var allowPinning: Bool {
        searchModel.selectedPinboardID != nil
    }

    private var isDragEnabled: Bool {
        true
    }

    private var isReorderingEnabled: Bool {
        isDragEnabled && searchModel.selectedPinboardID != nil && !isSearchActive
    }

    private var itemsSourceAppsHash: Int {
        items.map { $0.sourceAppBundleID ?? $0.sourceAppName ?? "" }
            .sorted()
            .joined()
            .hashValue
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)

            VStack(alignment: .leading, spacing: 14) {
                // Header Bar
                ZStack(alignment: .center) {
                    // Center: Pinboards
                    PinboardTabBar(
                        pinboards: visiblePinboards,
                        selectedID: searchModel.selectedPinboardID,
                        editingID: $renamePinboardID,
                        isCreating: $isCreatingPinboard,
                        draftName: $renamePinboardName,
                        draftColor: $renamePinboardColor,
                        isGlobalDragActive: dragCoordinator.dragPreviewData != nil,
                        onSelect: { id in
                            closeSearchIfEmpty()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                        onMoveItem: pinboardManager.moveItemToPinboard,
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
                        frameCoordinator.updateCapturedPinboardLayout(layout)
                        dragCoordinator.updatePinboardLayout(layout)
                    }
                    .onPreferenceChange(SearchFieldFrameKey.self) { frame in
                        dragCoordinator.updateSearchFieldFrame(frame)
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

                Group {
                    if filteredItems.isEmpty {
                        emptyStateView
                            .padding(.horizontal, 14)
                    } else {
                        ItemCardRow(
                            items: filteredItems,
                            pinboards: visiblePinboards,
                            mode: viewModel.mode,
                            selectedItemIDs: viewModel.selectedItemIDs,
                            editingItemID: renameItemID,
                            allowPinning: allowPinning,
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
                            onMoveToPinboard: pinboardManager.toggleItem,
                            onCreatePinboard: { beginPinboardCreate(for: $0) },
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
                            }
                        )
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
            if isFilterPopoverPresented {
                searchModel.updateAppOptions(from: Array(items))
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
        .onAppear {
            searchFocused = true
            modifierMonitor.start()
            ensureValidSelection()
            dragCoordinator.ensurePreviewWindow()
        }
        .onDisappear {
            modifierMonitor.stop()
            dragCoordinator.cleanupPreviewWindow()

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
        .onChange(of: pinboards.count) {
            ensureValidSelection()
        }
        .onChange(of: itemsSourceAppsHash) {
            if isFilterPopoverPresented {
                searchModel.updateAppOptions(
                    from: Array(items))
            }
        }
        .onReceive(eventBroadcaster.events) { event in
            if event == .overlayDidShow {
                searchFocused = true
                announceOverlayItemCount()
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

    private func copyItem(_ item: ClipItem) {
        itemOperationsHandler.copyItem(
            item,
            selectedItemIDs: viewModel.selectedItemIDs,
            orderedItems: filteredItems,
            eventBroadcaster: eventBroadcaster
        )
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
                searchModel.updateAppOptions(from: Array(items))
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
        guard let selectedPinboardID = searchModel.selectedPinboardID,
            let selected = pinboards.first(where: { $0.id == selectedPinboardID }),
            selected.isSystemClipboard
        else { return }
        searchModel.selectedPinboardID = nil
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

    private func sortItems(_ items: [ClipItem]) -> [ClipItem] {
        guard searchModel.selectedPinboardID != nil else {
            return items.sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
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

private struct SearchFieldFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@available(macOS 14.0, *)
private struct OverlaySettingsButton14: View {
    let closeOverlay: (@escaping () -> Void) -> Void
    let label: AnyView

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            closeOverlay {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
        } label: {
            label
        }
    }
}

private struct RenameOverlayView: View {
    @Binding var title: String
    var onSave: () -> Void
    var onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Item")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit {
                    onSave()
                }
                .accessibilityIdentifier("overlay.rename.title")
                .accessibilityLabel("Title")
                .accessibilityValue(title.isEmpty ? "Empty" : title)
                .accessibilityHint("Enter a new title")

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("overlay.rename.cancel")
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismisses without saving")

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("overlay.rename.save")
                .accessibilityLabel("Save")
                .accessibilityHint("Saves the new title")
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

private struct ResizeHandleView: View {
    let window: NSWindow?
    @State private var isDragging = false

    // Resize State
    @State private var anchorY: CGFloat = 0
    @State private var clickOffsetY: CGFloat = 0

    var body: some View {
        VStack {
            ZStack {
                ResizeHandleCursorView()
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .accessibilityIdentifier("overlay.resizeHandle")
            .accessibilityLabel("Resize overlay")
            .accessibilityHint("Drag up or down to resize")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard let window = window else { return }

                        // Initialize state on first drag event
                        if !isDragging {
                            isDragging = true

                            // Capture the "Bottom" of the window (Anchor)
                            anchorY = window.frame.minY

                            // Capture where the mouse is relative to the "Top" of the window
                            let currentTopY = window.frame.maxY
                            let mouseScreenY = NSEvent.mouseLocation.y
                            clickOffsetY = currentTopY - mouseScreenY
                        }

                        let mouseScreenY = NSEvent.mouseLocation.y
                        let targetTopY = mouseScreenY + clickOffsetY
                        let newHeight = targetTopY - anchorY

                        // Clamp
                        let screenHeight = window.screen?.visibleFrame.height ?? 800
                        let maxHeight = min(screenHeight - 50, 400)
                        let minHeight: CGFloat = 220
                        let clamped = min(max(minHeight, newHeight), maxHeight)

                        var frame = window.frame
                        if frame.size.height != clamped {
                            frame.size.height = clamped
                            window.setFrame(frame, display: true)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        if let window = window {
                            UserDefaults.standard.set(window.frame.height, forKey: "OverlayHeight")
                        }
                    }
            )
            Spacer()
        }
    }
}

private struct ResizeHandleCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CursorRectView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CursorRectView: NSView {
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeUpDown)
        }
    }
}
