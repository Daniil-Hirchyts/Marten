import AppKit
import ClipboardCore
import ClipboardMacServices
import OSLog
import SwiftUI

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
    @State private var isHoveringResize = false
    @State private var startWindowHeight: CGFloat = 0
    @State private var isSearchExpanded = false
    @State private var pinboardFrames: [NSManagedObjectID: CGRect] = [:]
    @State private var allPinboardFrame: CGRect?
    @State private var pinboardEditorFrame: CGRect?
    @State private var searchFieldFrame: CGRect?
    @State private var isHoveringTop = false
    @State private var hoverTimer: Timer?
    
    private let store = ClipItemStore()
    private let overlayCoordinateSpaceName = "OverlaySpace"
    private let searchCollapsedWidth: CGFloat = 28
    private let searchExpandedWidth: CGFloat = 220
    private var headerSideWidth: CGFloat { searchExpandedWidth + 20 }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "displayOrder", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ],
        predicate: NSPredicate(format: "isTransient == NO"),
        animation: .easeInOut
    )
    private var items: FetchedResults<ClipItem>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)],
        animation: .easeInOut
    )
    private var pinboards: FetchedResults<Pinboard>

    @State private var selectedPinboardID: UUID?

    private var filteredItems: [ClipItem] {
        if isSearchActive {
            return sortItems(searchResults)
        }

        let query = searchText.normalizedForSearch()
        let baseItems = items.filter { item in
            guard let selectedPinboardID else { return true }
            return item.pinboards?.contains(where: { $0.id == selectedPinboardID }) ?? false
        }

        let filtered: [ClipItem]
        if query.isEmpty {
            filtered = Array(baseItems)
        } else {
            filtered = baseItems.filter {
                ($0.searchableText ?? "").contains(query) || ($0.primaryText ?? "").normalizedForSearch().contains(query)
            }
        }

        return sortItems(filtered)
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visiblePinboards: [Pinboard] {
        pinboards.filter { !$0.isSystemClipboard }
    }

    private var allowPinning: Bool {
        selectedPinboardID != nil
    }

    private var isDragEnabled: Bool {
        viewModel.mode == .browse && !isSearchActive
    }

    private var isReorderingEnabled: Bool {
        isDragEnabled && selectedPinboardID != nil
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
                        onSelect: { id in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedPinboardID = id
                            }
                        },
                        onCreate: {
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
                    .onPreferenceChange(PinboardFrameKey.self) { frames in
                        pinboardFrames = frames
                    }
                    .onPreferenceChange(PinboardAllFrameKey.self) { frame in
                        allPinboardFrame = frame
                    }
                    .onPreferenceChange(PinboardEditorFrameKey.self) { frame in
                        pinboardEditorFrame = frame
                    }
                    .onPreferenceChange(SearchFieldFrameKey.self) { frame in
                        searchFieldFrame = frame
                    }

                    // Left: Search
                    HStack(alignment: .center) {
                        HStack(spacing: 0) {
                            // Search Icon / Toggle
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 30, height: 30)
                                    .opacity(isSearchExpanded ? 0 : 1)
                                
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 30, height: 30)
                            .onTapGesture {
                                if !isSearchExpanded {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isSearchExpanded = true
                                        searchFocused = true
                                    }
                                }
                            }

                            if isSearchExpanded {
                                HStack(spacing: 8) {
                                    TextField("Search", text: $searchText)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .tint(.white)
                                        .focused($searchFocused)
                                    
                                    // Close search button (on the right)
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            isSearchExpanded = false
                                            searchText = ""
                                            searchFocused = false
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(4)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.leading, 8)
                                .padding(.trailing, 4)
                            }
                        }
                        .padding(isSearchExpanded ? 4 : 0)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .opacity(isSearchExpanded ? 1 : 0)
                        )
                        .frame(
                            width: isSearchExpanded ? searchExpandedWidth : 30,
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
                    }
                    .frame(width: headerSideWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4) // Adjust padding

                    // Right: Settings
                    HStack {
                        Spacer()
                        Button(action: openSettings) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 40)
                .zIndex(1)

                if viewModel.mode == .pasteStack {
                    Text("Paste Stack")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 4)
                }

                Group {
                    if filteredItems.isEmpty {
                        emptyStateView
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
                            coordinateSpaceName: overlayCoordinateSpaceName,
                            pinboardFrames: pinboardFrames,
                            allPinboardFrame: allPinboardFrame,
                            window: window
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
                }
            }
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Resize Handle Area
            VStack {
                ZStack {
                    Color.clear
                    if isHoveringTop || isHoveringResize {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 36, height: 4)
                            .shadow(radius: 2)
                            .transition(.opacity)
                    }
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringResize = hovering
                    if hovering {
                        NSCursor.resizeUpDown.push()
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHoveringTop = true
                        }
                        hoverTimer?.invalidate()
                        hoverTimer = nil
                    } else {
                        NSCursor.pop()
                        hoverTimer?.invalidate()
                        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                            withAnimation(.easeIn(duration: 0.2)) {
                                isHoveringTop = false
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { _ in
                            // Ensure visible and cancel hide timer during drag
                            withAnimation(.easeOut(duration: 0.2)) {
                                isHoveringTop = true
                            }
                            hoverTimer?.invalidate()
                            hoverTimer = nil
                            
                            guard let window = window else { return }
                            
                            // Use absolute Cocoa screen coordinates (Origin: Bottom-Left)
                            // This avoids SwiftUI coordinate space translation issues during window resizing
                            let mouseLocation = NSEvent.mouseLocation
                            let newHeight = mouseLocation.y - window.frame.minY
                            
                            // Clamp height
                            // Max height relative to screen, leaving some buffer
                            // Min height 280 to prevent card content clipping
                            let screenHeight = window.screen?.visibleFrame.height ?? 800
                            let maxHeight = min(screenHeight - 50, 400)
                            let minHeight: CGFloat = 280
                            let clamped = min(max(minHeight, newHeight), maxHeight)
                            
                            var frame = window.frame
                            frame.size.height = clamped
                            window.setFrame(frame, display: true)
                        }
                        .onEnded { _ in
                            if let window = window {
                                UserDefaults.standard.set(window.frame.height, forKey: "OverlayHeight")
                            }
                            // Start hide timer after drag ends
                            hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                                withAnimation(.easeIn(duration: 0.2)) {
                                    isHoveringTop = false
                                }
                            }
                        }
                )
                Spacer()
            }
        }
        .coordinateSpace(name: overlayCoordinateSpaceName)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(overlayCoordinateSpaceName))
                .onEnded { value in
                    handleOverlayTap(at: value.location)
                }
        )
        .background(WindowAccessor(window: $window))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
        .onAppear {
            searchFocused = true
            modifierMonitor.start()
            ensureValidSelection()
            // Reset resize state
            isHoveringTop = false
            isHoveringResize = false
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
        .onDisappear {
            modifierMonitor.stop()
            // Cleanup timer
            hoverTimer?.invalidate()
            hoverTimer = nil
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
            return "No results for \"\(searchText)\". Try another keyword."
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
            selectedPinboardID = pinboard.id
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
        viewModel.selectItem(
            item,
            in: filteredItems,
            isShiftPressed: modifierMonitor.isShiftPressed,
            isCommandPressed: modifierMonitor.isCommandPressed
        )
    }

    private func handleCardDoubleTap(_ item: ClipItem) {
        if viewModel.mode == .browse {
            viewModel.paste(item: item, plainText: modifierMonitor.isShiftPressed)
        }
    }

    private func openSettings() {
        // Placeholder for Phase 4 Settings implementation
        // If the App delegate responds to showSettingsWindow:, it will be called.
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
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isSearchExpanded = false
                searchText = ""
                searchFocused = false
            }
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

}

private struct SearchFieldFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
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
