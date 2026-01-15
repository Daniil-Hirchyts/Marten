import AppKit
import ClipboardCore
import ClipboardMacServices
import OSLog
import SwiftUI

// Approximate equality for CGRect to handle floating-point precision issues
// Using higher tolerance (5.0) to prevent layout jitter from triggering updates
private func overlayFramesApproximatelyEqual(
    _ lhs: [NSManagedObjectID: CGRect],
    _ rhs: [NSManagedObjectID: CGRect],
    tolerance: CGFloat = 5.0
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key, lhsRect) in lhs {
        guard let rhsRect = rhs[key] else { return false }
        if abs(lhsRect.origin.x - rhsRect.origin.x) > tolerance ||
           abs(lhsRect.origin.y - rhsRect.origin.y) > tolerance ||
           abs(lhsRect.size.width - rhsRect.size.width) > tolerance ||
           abs(lhsRect.size.height - rhsRect.size.height) > tolerance {
            return false
        }
    }
    return true
}

private func overlayRectApproximatelyEqual(
    _ lhs: CGRect?,
    _ rhs: CGRect?,
    tolerance: CGFloat = 5.0
) -> Bool {
    guard let lhs = lhs, let rhs = rhs else { return lhs == nil && rhs == nil }
    return abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
           abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
           abs(lhs.size.width - rhs.size.width) <= tolerance &&
           abs(lhs.size.height - rhs.size.height) <= tolerance
}

struct OverlayRootView: View {
    @EnvironmentObject private var viewModel: OverlayViewModel
    @State private var searchText = ""
    @State private var renamePinboardID: NSManagedObjectID?
    @State private var renamePinboardName = ""
    @State private var renamePinboardColor = PinboardPalette.defaultHex
    @State private var isCreatingPinboard = false
    @State private var pendingPinboardItem: ClipItem?
    @State private var renameItemID: NSManagedObjectID?
    @State private var searchResults: [ClipItem] = []
    @FocusState private var searchFocused: Bool
    @StateObject private var modifierMonitor = ModifierKeyMonitor()
    @State private var window: NSWindow?
    @State private var isSearchExpanded = false
    @State private var searchDateFilter: SearchDateFilter = .any
    @State private var searchTypeFilters: Set<ItemType> = []
    @State private var searchAppFilters: Set<String> = []
    @State private var pinboardFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var allPinboardFrame: CGRect?
    @State private var pinboardEditorFrame: CGRect?
    @State private var searchFieldFrame: CGRect?
    @State private var dragPreviewData: DragPreviewData?
    
    // Non-reactive storage for drop target detection during drag
    // Captured when shouldReportFrames is true, then adjusted by scroll delta
    static var capturedPinboardFrames: [NSManagedObjectID: CGRect] = [:]
    static var capturedAllPinboardFrame: CGRect?
    static var capturedScrollOffset: CGFloat = 0
    @State private var dragPreviewWindow: DragPreviewWindow?
    @State private var isFilterPopoverPresented = false
    
    private let store = ClipItemStore()
    private let overlayCoordinateSpaceName = "OverlaySpace"
    private let headerButtonSize: CGFloat = 30
    private let headerButtonIconSize: CGFloat = 14
    private let searchCollapsedWidth: CGFloat = 30
    private let searchExpandedWidth: CGFloat = 220
    private var headerSideWidth: CGFloat { searchExpandedWidth + 20 }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "displayOrder", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
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

    @State private var selectedPinboardID: UUID?

    private var filteredItems: [ClipItem] {
        let baseItems = items.filter { item in
            guard let selectedPinboardID else { return true }
            return item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false
        }
        let baseList = isSearchTextActive ? searchResults : Array(baseItems)
        let filtered = applySearchFilters(to: baseList)
        return sortItems(filtered)
    }

    private var isSearchActive: Bool {
        isSearchTextActive || hasActiveFilters
    }

    private var isSearchTextActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasActiveFilters: Bool {
        searchDateFilter != .any || !searchTypeFilters.isEmpty || !searchAppFilters.isEmpty
    }

    private var visiblePinboards: [Pinboard] {
        pinboards.filter { !$0.isSystemClipboard }
    }

    private var allowPinning: Bool {
        selectedPinboardID != nil
    }

    private var isDragEnabled: Bool {
        viewModel.mode == .browse
    }

    private var isReorderingEnabled: Bool {
        isDragEnabled && selectedPinboardID != nil && !isSearchActive
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
                        selectedID: selectedPinboardID,
                        editingID: $renamePinboardID,
                        isCreating: $isCreatingPinboard,
                        draftName: $renamePinboardName,
                        draftColor: $renamePinboardColor,
                        isGlobalDragActive: dragPreviewData != nil,
                        onSelect: { id in
                            closeSearchIfEmpty()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedPinboardID = id
                            }
                        },
                        onCreate: {
                            closeSearchIfEmpty()
                            // Smart Color Selection
                            let usedColors = Set(pinboards.map { $0.colorHex })
                            let availableColors = PinboardPalette.colors.filter { !usedColors.contains($0) }
                            renamePinboardColor = availableColors.first ?? PinboardPalette.colors.randomElement() ?? PinboardPalette.defaultHex
                            
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
                        onColorChange: changePinboardColor,
                        onDelete: deletePinboard,
                        onReorder: reorderPinboards,
                        onReorderEnd: finalizeReorder,
                        onMoveItem: moveItemToPinboard,
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
                    .onPreferenceChange(PinboardFrameKey.self) { frames in
                        // ALWAYS capture for static storage (used by ItemCardRow during drag)
                        Self.capturedPinboardFrames = frames
                        // Skip reactive state updates during drag to prevent re-render loops
                        guard dragPreviewData == nil else { return }
                        // Use approximate equality to avoid floating-point precision issues
                        if !overlayFramesApproximatelyEqual(frames, pinboardFrames) {
                            pinboardFrames = frames
                        }
                    }
                    .onPreferenceChange(PinboardAllFrameKey.self) { frame in
                        // ALWAYS capture for static storage (used by ItemCardRow during drag)
                        Self.capturedAllPinboardFrame = frame
                        Self.capturedScrollOffset = PinboardTabBar.currentScrollOffset
                        // Skip reactive state updates during drag
                        guard dragPreviewData == nil else { return }
                        if !overlayRectApproximatelyEqual(frame, allPinboardFrame) {
                            allPinboardFrame = frame
                        }
                    }
                    .onPreferenceChange(PinboardEditorFrameKey.self) { frame in
                        guard dragPreviewData == nil else { return }
                        if !overlayRectApproximatelyEqual(frame, pinboardEditorFrame) {
                            pinboardEditorFrame = frame
                        }
                    }
                    .onPreferenceChange(SearchFieldFrameKey.self) { frame in
                        guard dragPreviewData == nil else { return }
                        if !overlayRectApproximatelyEqual(frame, searchFieldFrame) {
                            searchFieldFrame = frame
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

                            if isSearchExpanded {
                                HStack(spacing: 6) {
                                    TextField("Search", text: $searchText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .tint(.white)
                                        .focused($searchFocused)
                                        .frame(height: headerButtonSize)
                                    
                                    // Close search button (on the right)
                                    Button(action: {
                                        isFilterPopoverPresented = false
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            isSearchExpanded = false
                                            searchText = ""
                                            searchFocused = false
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(3)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 6)
                            }
                        }
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .opacity(isSearchExpanded ? 1 : 0)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(isSearchExpanded ? 0.3 : 0), lineWidth: 1)
                        )
                        .frame(
                            width: isSearchExpanded ? searchExpandedWidth : searchCollapsedWidth,
                            height: headerButtonSize,
                            alignment: .leading
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearchExpanded)
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
                    .padding(.leading, 4) // Adjust padding

                    // Right: Settings
                    HStack {
                        Spacer()
                        Button(action: openSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: headerButtonIconSize, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: headerButtonSize, height: headerButtonSize)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 14)
                .frame(height: headerButtonSize)
                .zIndex(1)

                if viewModel.mode == .pasteStack {
                    Text("Paste Stack")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14 + 4)
                }

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
                            onPaste: { pasteItem($0, plainText: false) },
                            onPastePlainText: { pasteItem($0, plainText: true) },
                            onCopy: copyItem,
                            onDelete: deleteItem,
                            onTogglePin: togglePin,
                            onMoveToPinboard: moveItem,
                            onCreatePinboard: { beginPinboardCreate(for: $0) },
                            onRename: renameItem,
                            onCommitRename: { item, newTitle in
                                commitItemRename(item: item, newTitle: newTitle)
                            },
                            onTap: handleCardTap,
                            onDoubleTap: handleCardDoubleTap,
                            onReorder: reorderItems,
                            onReorderEnd: finalizeReorder,
                            onDropToPinboard: handleDropToPinboard,
                            onDropToAll: handleDropToAll,
                            onPasteOutside: pasteItemsOutside,
                            coordinateSpaceName: overlayCoordinateSpaceName,
                            pinboardFrames: pinboardFrames,
                            allPinboardFrame: allPinboardFrame,
                            window: window,
                            dragPreviewData: $dragPreviewData,
                            onPreviewUpdate: { data in
                                // Direct preview update - bypasses SwiftUI state for better performance
                                updateDragPreviewWindow(data)
                            }
                        )
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)

                if viewModel.mode == .pasteStack {
                    PasteStackFooterBar(
                        selectionCount: viewModel.selectedItemIDs.count,
                        isPlainText: modifierMonitor.isShiftPressed,
                        isPasting: viewModel.isPasting,
                        onClear: viewModel.clearSelection,
                        onPaste: { viewModel.pasteStack(plainText: modifierMonitor.isShiftPressed) }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
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
        .onChange(of: dragPreviewData) { newData in
            updateDragPreviewWindow(newData)
        }
        .alert("Accessibility Permission Required", isPresented: $viewModel.showAccessibilityAlert) {
            Button("Open System Settings") {
                viewModel.requestAccessibility()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste needs Accessibility permission to paste into other apps.")
        }
        .onChange(of: searchText) { _ in
            updateSearchResults()
        }
        .onChange(of: selectedPinboardID) { _ in
            updateSearchResults()
        }
        .onChange(of: isSearchExpanded) { expanded in
            if !expanded {
                isFilterPopoverPresented = false
            }
        }
        .onChange(of: searchFocused) { focused in
            // Close empty search when focus is lost
            if !focused && isSearchExpanded && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                    isSearchExpanded = false
                }
            }
        }
        .onAppear {
            searchFocused = true
            modifierMonitor.start()
            ensureValidSelection()

            // Initialize drag preview window
            if dragPreviewWindow == nil {
                dragPreviewWindow = DragPreviewWindow()
            }
        }
        .onDisappear {
            modifierMonitor.stop()

            // Cleanup drag preview window
            dragPreviewWindow?.orderOut(nil)
            dragPreviewWindow = nil
            
            // Close search on overlay close only if empty
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchExpanded = false
                searchFocused = false
            }
            isFilterPopoverPresented = false
            
            // Allow clean state for next time
            isCreatingPinboard = false
            renamePinboardID = nil
        }
        .onChange(of: pinboards.count) { _ in
            ensureValidSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayDidShow)) { _ in
            searchFocused = true
        }
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

    private var emptyStateText: String {
        if isSearchActive {
            if isSearchTextActive {
                return "No results for \"\(searchText)\". Try another keyword."
            }
            return "No results for the current filters."
        }
        if selectedPinboardID != nil {
            return "No items in this pinboard"
        }
        return "Copy something to get started."
    }

    private func copyItem(_ item: ClipItem) {
        if viewModel.selectedItemIDs.count > 1 && viewModel.selectedItemIDs.contains(item.objectID) {
            copySelectedItems()
        } else {
            guard let text = item.primaryText, !text.isEmpty else { return }
            NotificationCenter.default.post(name: .clipboardWillWrite, object: nil)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    private func deleteItem(_ item: ClipItem) {
        if viewModel.selectedItemIDs.count > 1 && viewModel.selectedItemIDs.contains(item.objectID) {
            deleteSelectedItems()
        } else {
            do {
                try store.deleteItem(objectID: item.objectID)
            } catch {
                Logger.app.error("Failed to delete item: \(error.localizedDescription)")
            }
        }
    }

    private func copySelectedItems() {
        let selectedItems = filteredItems.filter { viewModel.selectedItemIDs.contains($0.objectID) }
        let texts = selectedItems.compactMap { $0.primaryText }.filter { !$0.isEmpty }
        guard !texts.isEmpty else { return }

        NotificationCenter.default.post(name: .clipboardWillWrite, object: nil)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(texts.joined(separator: "\n"), forType: .string)
    }

    private func deleteSelectedItems() {
        let idsToDelete = Array(viewModel.selectedItemIDs)
        viewModel.clearSelection()
        for objectID in idsToDelete {
            do {
                try store.deleteItem(objectID: objectID)
            } catch {
                Logger.app.error("Failed to delete item: \(error.localizedDescription)")
            }
        }
    }

    private func pasteItem(_ item: ClipItem, plainText: Bool) {
        if viewModel.selectedItemIDs.count > 1 && viewModel.selectedItemIDs.contains(item.objectID) {
            pasteSelectedItems(plainText: plainText)
        } else {
            viewModel.paste(item: item, plainText: plainText)
        }
    }

    private func pasteSelectedItems(plainText: Bool) {
        guard viewModel.selectedItemIDs.count > 0 else { return }
        let selectedItems = filteredItems.filter { viewModel.selectedItemIDs.contains($0.objectID) }
        guard let firstItem = selectedItems.first else { return }

        if selectedItems.count == 1 {
            viewModel.paste(item: firstItem, plainText: plainText)
        } else {
            // For multiple items in browse mode, switch to paste stack mode preserving selection
            if viewModel.mode == .browse {
                let selectedIDs = viewModel.selectedItemIDs
                viewModel.setMode(.pasteStack)
                viewModel.restoreSelection(selectedIDs, in: filteredItems)
            }
            viewModel.pasteStack(plainText: plainText)
        }
    }

    private func pasteItemsOutside(_ itemIDs: [NSManagedObjectID]) {
        let plainText = modifierMonitor.isShiftPressed
        let draggedItems = filteredItems.filter { itemIDs.contains($0.objectID) }
        guard let firstItem = draggedItems.first else {
            return
        }

        // Small delay to ensure drag gesture is fully complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [viewModel] in
            if draggedItems.count == 1 {
                viewModel.paste(item: firstItem, plainText: plainText)
            } else {
                // For multiple items, switch to paste stack mode and paste
                if viewModel.mode == .browse {
                    viewModel.setMode(.pasteStack)
                    viewModel.restoreSelection(Set(itemIDs), in: draggedItems)
                }
                viewModel.pasteStack(plainText: plainText)
            }
        }
    }

    private func renameItem(_ item: ClipItem) {
        renameItemID = item.objectID
    }

    private func commitItemRename(item: ClipItem, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.renameItem(objectID: item.objectID, title: trimmed.isEmpty ? nil : trimmed)
        } catch {
            Logger.app.error("Failed to rename item: \(error.localizedDescription)")
        }
        renameItemID = nil
    }

    private func togglePin(_ item: ClipItem) {
        guard allowPinning else { return }
        let context = item.managedObjectContext
        context?.perform {
            item.isPinned.toggle()
            if item.isPinned {
                item.displayOrder = Int64(Date().timeIntervalSince1970 * 1000)
            }
            do {
                try context?.save()
            } catch {
                Logger.app.error("Failed to toggle pin: \(error.localizedDescription)")
            }
        }
    }

    private func deletePinboard(_ pinboard: Pinboard) {
        guard !pinboard.isSystemClipboard else { return }
        if selectedPinboardID == pinboard.id {
            selectedPinboardID = nil
        }
        do {
            try store.deletePinboard(objectID: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to delete pinboard: \(error.localizedDescription)")
        }
    }

    private func commitPinboardRename() {
        guard let objectID = renamePinboardID else { return }
        let trimmedName = renamePinboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            try store.renamePinboard(objectID: objectID, name: trimmedName, colorHex: renamePinboardColor)
        } catch {
            Logger.app.error("Failed to rename pinboard: \(error.localizedDescription)")
        }
    }

    private func commitPinboardCreate() {
        let trimmedName = renamePinboardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            let pinboard = try store.createPinboard(name: trimmedName, colorHex: renamePinboardColor)
            if let pendingPinboardItem {
                try? store.moveItem(objectID: pendingPinboardItem.objectID, toPinboard: pinboard.objectID)
            }
            pendingPinboardItem = nil
        } catch {
            Logger.app.error("Failed to create pinboard: \(error.localizedDescription)")
        }
    }

    private func updateSearchResults() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try store.searchItems(query: trimmed, limit: 100, pinboardID: selectedPinboardID)
        } catch {
            Logger.app.error("Search failed: \(error.localizedDescription)")
            searchResults = []
        }
    }

    private func applySearchFilters(to items: [ClipItem]) -> [ClipItem] {
        guard hasActiveFilters else { return items }
        return items.filter { item in
            if !matchesDateFilter(item) {
                return false
            }
            if !searchTypeFilters.isEmpty, !searchTypeFilters.contains(item.itemTypeValue) {
                return false
            }
            if !searchAppFilters.isEmpty {
                guard let key = appFilterKey(for: item) else { return false }
                if !searchAppFilters.contains(key) {
                    return false
                }
            }
            return true
        }
    }

    private func matchesDateFilter(_ item: ClipItem) -> Bool {
        switch searchDateFilter {
        case .any:
            return true
        case .today:
            return Calendar.current.isDateInToday(item.createdAt)
        case .last7Days:
            return item.createdAt >= dateCutoff(days: 7)
        case .last30Days:
            return item.createdAt >= dateCutoff(days: 30)
        }
    }

    private func dateCutoff(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
    }

    private func appFilterKey(for item: ClipItem) -> String? {
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
            return bundleID
        }
        if let name = item.sourceAppName, !name.isEmpty {
            return name
        }
        return nil
    }

    private var appFilterOptions: [AppFilterOption] {
        let baseItems = items.filter { item in
            guard let selectedPinboardID else { return true }
            return item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false
        }
        var options: [String: AppFilterOption] = [:]
        for item in baseItems {
            guard let key = appFilterKey(for: item) else { continue }
            let name = item.sourceAppName?.isEmpty == false ? item.sourceAppName! : key
            if options[key] == nil {
                let bundleID = item.sourceAppBundleID
                var icon: NSImage?
                if let bundleID,
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                }
                options[key] = AppFilterOption(id: key, name: name, bundleID: bundleID, icon: icon)
            }
        }
        return options
            .map(\.value)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var searchIcon: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: headerButtonSize, height: headerButtonSize)
                .opacity(isSearchExpanded ? 0 : 1)

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)

            if hasActiveFilters {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .offset(x: 9, y: -9)
            }
        }
        .frame(width: headerButtonSize, height: headerButtonSize)
    }

    private var searchFilterPopover: some View {
        FilterPopoverView(
            dateFilter: $searchDateFilter,
            typeFilters: $searchTypeFilters,
            appFilters: $searchAppFilters,
            appOptions: appFilterOptions,
            onClear: clearSearchFilters
        )
    }

    private func handleSearchButtonTap() {
        if isSearchExpanded {
            isFilterPopoverPresented.toggle()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSearchExpanded = true
                searchFocused = true
            }
        }
    }

    private func clearSearchFilters() {
        searchDateFilter = .any
        searchTypeFilters.removeAll()
        searchAppFilters.removeAll()
    }

    private func ensureValidSelection() {
        guard let selectedPinboardID,
              let selected = pinboards.first(where: { $0.id == selectedPinboardID }),
              selected.isSystemClipboard else { return }
        self.selectedPinboardID = nil
    }

    private func beginPinboardCreate(for item: ClipItem?) {
        pendingPinboardItem = item
        
        let usedColors = Set(pinboards.map { $0.colorHex })
        let availableColors = PinboardPalette.colors.filter { !usedColors.contains($0) }
        renamePinboardColor = availableColors.first ?? PinboardPalette.colors.randomElement() ?? PinboardPalette.defaultHex
        
        renamePinboardName = ""
        isCreatingPinboard = true
    }

    private func moveItem(_ item: ClipItem, to pinboard: Pinboard) {
        do {
            try store.moveItem(objectID: item.objectID, toPinboard: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
        }
    }

    private func sortItems(_ items: [ClipItem]) -> [ClipItem] {
        guard selectedPinboardID != nil else {
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

    private func reorderItems(_ draggedIDs: [NSManagedObjectID], _ target: ClipItem, insertBefore: Bool) {
        guard viewModel.mode == .browse, !isSearchActive else { return }

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
    
    private func moveItemToPinboard(_ pinboard: Pinboard, _ idString: String) {
        guard let url = URL(string: idString),
              let objectID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) else { return }
        
        do {
            try store.moveItem(objectID: objectID, toPinboard: pinboard.objectID)
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
        }
    }

    private func handleDropToPinboard(_ item: ClipItem, _ pinboardID: NSManagedObjectID) {
        do {
            try store.moveItem(objectID: item.objectID, toPinboard: pinboardID)
            viewModel.clearSelection()
            // Update search results if search is active to reflect the change
            if isSearchTextActive {
                updateSearchResults()
            }
        } catch {
            Logger.app.error("Failed to move item to pinboard: \(error.localizedDescription)")
        }
    }

    private func handleDropToAll(_ item: ClipItem) {
        guard let selectedPinboardID,
              let pinboard = pinboards.first(where: { $0.id == selectedPinboardID }) else {
            return
        }

        do {
            try store.removeItem(objectID: item.objectID, fromPinboard: pinboard.objectID)
            viewModel.clearSelection()
        } catch {
            Logger.app.error("Failed to remove item from pinboard: \(error.localizedDescription)")
        }
    }

    private func reorderPinboards(_ dragged: Pinboard, _ target: Pinboard, insertBefore: Bool) {
        guard !dragged.isSystemClipboard, !target.isSystemClipboard else { return }

        var ordered = visiblePinboards
        guard let fromIndex = ordered.firstIndex(where: { $0.objectID == dragged.objectID }),
              var toIndex = ordered.firstIndex(where: { $0.objectID == target.objectID }),
              fromIndex != toIndex else { return }

        // If inserting after, adjust target index
        if !insertBefore {
            toIndex += 1
        }

        // Remove the dragged pinboard
        let movedItem = ordered.remove(at: fromIndex)

        // Calculate the correct insertion index after removal
        let adjustedIndex: Int
        if fromIndex < toIndex {
            adjustedIndex = toIndex - 1
        } else {
            adjustedIndex = toIndex
        }

        // Insert at the adjusted position
        ordered.insert(movedItem, at: adjustedIndex)

        // Optimistic Update
        for (index, pinboard) in ordered.enumerated() {
            pinboard.sortOrder = Int16(index)
        }
    }
    
    private func finalizeReorder() {
        do {
            try store.saveChanges()
        } catch {
            Logger.app.error("Failed to save reorder: \(error.localizedDescription)")
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
        if viewModel.mode == .browse {
            viewModel.paste(item: item, plainText: modifierMonitor.isShiftPressed)
        }
    }
    
    /// Closes search only if it's expanded AND the search text is empty
    private func closeSearchIfEmpty() {
        guard isSearchExpanded, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isFilterPopoverPresented = false
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
            isSearchExpanded = false
            searchFocused = false
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func changePinboardColor(_ pinboard: Pinboard, hex: String) {
        do {
            try store.renamePinboard(objectID: pinboard.objectID, name: pinboard.name, colorHex: hex)
        } catch {
            Logger.app.error("Failed to change pinboard color: \(error.localizedDescription)")
        }
    }

    private func handleOverlayTap(at location: CGPoint) {
        if isSearchExpanded,
           let searchFieldFrame,
           !searchFieldFrame.contains(location) {
            closeSearchIfEmpty()
        }

        guard (isCreatingPinboard || renamePinboardID != nil),
              let pinboardEditorFrame,
              !pinboardEditorFrame.contains(location) else { return }

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

    private func updateDragPreviewWindow(_ data: DragPreviewData?) {
        guard let dragPreviewWindow = dragPreviewWindow,
              window != nil else { return }

        if let data = data {
            // Get actual mouse location in screen coordinates
            let mouseLocation = NSEvent.mouseLocation

            // Position the 600x600 preview window centered on the actual mouse position
            let previewFrame = NSRect(
                x: mouseLocation.x - 300,
                y: mouseLocation.y - 300,
                width: 600,
                height: 600
            )

            dragPreviewWindow.setFrame(previewFrame, display: false)
            dragPreviewWindow.updatePreview(data)
        } else {
            dragPreviewWindow.updatePreview(nil)
        }
    }

}

private struct SearchFieldFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private enum SearchDateFilter: String, CaseIterable, Identifiable {
    case any
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any:
            return "Any time"
        case .today:
            return "Today"
        case .last7Days:
            return "Last 7 days"
        case .last30Days:
            return "Last 30 days"
        }
    }
}

private struct AppFilterOption: Identifiable {
    let id: String
    let name: String
    let bundleID: String?
    let icon: NSImage?
}

private struct FilterPopoverView: View {
    @Binding var dateFilter: SearchDateFilter
    @Binding var typeFilters: Set<ItemType>
    @Binding var appFilters: Set<String>
    let appOptions: [AppFilterOption]
    let onClear: () -> Void

    private let popoverWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Filters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Clear all") {
                    onClear()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasActiveFilters ? .secondary : .tertiary)
                .disabled(!hasActiveFilters)
            }

            filterSection(title: "Date", icon: "calendar") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(SearchDateFilter.allCases) { filter in
                        FilterChip(
                            title: filter.title,
                            icon: dateIcon(for: filter),
                            isSelected: dateFilter == filter
                        ) {
                            dateFilter = filter
                        }
                    }
                }
            }

            filterSection(title: "Type", icon: "square.3.layers.3d") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(ItemType.allCases, id: \.self) { type in
                        FilterChip(
                            title: itemTypeLabel(type),
                            icon: itemTypeIcon(type),
                            isSelected: typeFilters.contains(type)
                        ) {
                            toggleType(type)
                        }
                    }
                }
            }

            filterSection(title: "App", icon: "app.dashed") {
                if appOptions.isEmpty {
                    Text("No apps found")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(appOptions) { option in
                                AppFilterChip(
                                    option: option,
                                    isSelected: appFilters.contains(option.id)
                                ) {
                                    toggleApp(option.id)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
        .padding(16)
        .frame(width: popoverWidth)
    }

    private var hasActiveFilters: Bool {
        dateFilter != .any || !typeFilters.isEmpty || !appFilters.isEmpty
    }

    private func toggleType(_ type: ItemType) {
        if typeFilters.contains(type) {
            typeFilters.remove(type)
        } else {
            typeFilters.insert(type)
        }
    }

    private func toggleApp(_ id: String) {
        if appFilters.contains(id) {
            appFilters.remove(id)
        } else {
            appFilters.insert(id)
        }
    }

    private func itemTypeLabel(_ type: ItemType) -> String {
        switch type {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "URL"
        case .code:
            return "Code"
        case .mixed:
            return "Mixed"
        }
    }

    private func filterSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func dateIcon(for filter: SearchDateFilter) -> String {
        switch filter {
        case .any:
            return "clock"
        case .today:
            return "sun.max"
        case .last7Days:
            return "7.circle"
        case .last30Days:
            return "calendar"
        }
    }

    private func itemTypeIcon(_ type: ItemType) -> String {
        switch type {
        case .text:
            return "text.alignleft"
        case .richText:
            return "textformat"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .url:
            return "link"
        case .code:
            return "chevron.left.slash.chevron.right"
        case .mixed:
            return "square.stack.3d.up"
        }
    }
}

private struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.9) : Color.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.black : Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AppFilterChip: View {
    let option: AppFilterOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = option.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(option.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.black : Color.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}


private struct PasteStackFooterBar: View {
    let selectionCount: Int
    let isPlainText: Bool
    let isPasting: Bool
    let onClear: () -> Void
    let onPaste: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(selectionLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") {
                onClear()
            }
            .buttonStyle(.bordered)

            Button(pasteTitle) {
                onPaste()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectionCount == 0 || isPasting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }

    private var selectionLabel: String {
        if selectionCount == 1 {
            return "1 item selected"
        }
        return "\(selectionCount) items selected"
    }

    private var pasteTitle: String {
        if isPasting {
            return "Pasting..."
        }
        return isPlainText ? "Paste Plain Text" : "Paste"
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

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
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
                        let maxHeight = min(screenHeight - 50, 450)
                        let minHeight: CGFloat = 280
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
