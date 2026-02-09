@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import CoreData
import Foundation
import OSLog

final class OverlayViewModel: ObservableObject {
    @MainActor @Published var mode: OverlayMode = .browse
    @MainActor @Published var selectedItemIDs: Set<NSManagedObjectID> = []
    @MainActor @Published var showAccessibilityAlert = false
    @MainActor @Published var isPasting = false
    @MainActor @Published var syncError: Error?
    @MainActor @Published var isAuthenticating = false

    private let clipItemStore: ClipItemStore
    private let pasteEngine: any PasteEngineProtocol
    private let permissionManager: PermissionManager
    private let closeOverlayForPaste: (@escaping () -> Void) -> Void
    private let soundPlayer: SoundEffectPlayer
    private let selectionHandler = ItemSelectionHandler()

    private let userDefaults = UserDefaults.standard

    init(
        persistence: PersistenceController,
        pasteEngine: any PasteEngineProtocol,
        permissionManager: PermissionManager,
        soundPlayer: SoundEffectPlayer = SoundEffectPlayer(),
        closeOverlayForPaste: @escaping (@escaping () -> Void) -> Void
    ) {
        self.clipItemStore = ClipItemStore(persistence: persistence)
        self.pasteEngine = pasteEngine
        self.permissionManager = permissionManager
        self.soundPlayer = soundPlayer
        self.closeOverlayForPaste = closeOverlayForPaste
    }

    @MainActor
    convenience init(
        services: any AppServiceProviding,
        closeOverlayForPaste: @escaping (@escaping () -> Void) -> Void
    ) {
        guard let permissionManager = services.permissionManager as? PermissionManager else {
            preconditionFailure("AppServiceProviding.permissionManager must be a PermissionManager")
        }
        self.init(
            persistence: services.persistence,
            pasteEngine: services.pasteEngine,
            permissionManager: permissionManager,
            soundPlayer: services.soundPlayer,
            closeOverlayForPaste: closeOverlayForPaste
        )
    }

    @MainActor
    func resetState() {
        selectedItemIDs.removeAll()
        mode = .browse
    }

    @MainActor
    func isSelected(_ item: ClipItem) -> Bool {
        selectedItemIDs.contains(item.objectID)
    }

    @MainActor
    func selectItem(
        _ item: ClipItem, in orderedItems: [ClipItem], isShiftPressed: Bool, isCommandPressed: Bool
    ) {
        selectedItemIDs = selectionHandler.updatedSelection(
            currentSelection: selectedItemIDs,
            orderedItems: orderedItems,
            tappedItem: item,
            isShiftPressed: isShiftPressed,
            isCommandPressed: isCommandPressed
        )
    }

    @MainActor
    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    @MainActor
    func ensureDefaultSelection(in orderedItems: [ClipItem]) {
        guard !orderedItems.isEmpty else {
            selectedItemIDs.removeAll()
            return
        }

        let visibleIDs = Set(orderedItems.map(\.objectID))
        let validSelection = selectedItemIDs.intersection(visibleIDs)

        if !validSelection.isEmpty {
            if validSelection != selectedItemIDs {
                selectedItemIDs = validSelection
            }
            return
        }

        selectedItemIDs = [orderedItems[0].objectID]
    }

    @MainActor
    func restoreSelection(_ ids: Set<NSManagedObjectID>, in orderedItems: [ClipItem]) {
        selectedItemIDs = ids
    }

    private var selectionAnchorID: NSManagedObjectID?

    @MainActor
    func moveSelection(direction: Int, in orderedItems: [ClipItem], isShiftPressed: Bool = false) {
        guard !orderedItems.isEmpty else { return }

        // If nothing selected, select first item
        guard let firstSelectedID = selectedItemIDs.first else {
            selectedItemIDs = [orderedItems[0].objectID]
            selectionAnchorID = orderedItems[0].objectID
            return
        }
        
        // Find current focus index (start point for movement)
        // If we have an anchor, we should move relative to the "other end" of the selection
        // But for simplicity in arrow nav, we usually move relative to the last focused item.
        // Let's assume the "focus" is the item that changed last.
        // If we don't track focus explicitly, we can infer:
        // If moving Down (1), we probably want to extend from the max index?
        // Actually, standard behavior:
        // Anchor is fixed. Cursor moves.
        // Range = [Anchor ... Cursor]
        
        // Let's find the current "cursor".
        // If we just started shifting, cursor is the current selection (single).
        // If we are already multi-selecting, the cursor is the item we just added.
        // We need `selectionCursorID` ideally, but let's try to infer or just add it.
        // Adding `selectionCursorID` is safer.
        
        let cursorID = selectionCursorID ?? firstSelectedID
        guard let cursorIndex = orderedItems.firstIndex(where: { $0.objectID == cursorID }) else {
             // Fallback
            selectedItemIDs = [orderedItems[0].objectID]
            selectionAnchorID = orderedItems[0].objectID
            selectionCursorID = orderedItems[0].objectID
            return
        }

        let newIndex = cursorIndex + direction
        
        // Clamp to bounds
        guard newIndex >= 0 && newIndex < orderedItems.count else { return }
        
        let newItem = orderedItems[newIndex]
        
        if isShiftPressed {
            // Start of range selection?
            if selectionAnchorID == nil {
                selectionAnchorID = cursorID
            }
            
            guard let anchorID = selectionAnchorID,
                  let anchorIndex = orderedItems.firstIndex(where: { $0.objectID == anchorID })
            else {
                // Anchor lost? Reset
                selectedItemIDs = [newItem.objectID]
                selectionAnchorID = newItem.objectID
                selectionCursorID = newItem.objectID
                return
            }
            
            // Select range [Anchor ... NewIndex]
            let start = min(anchorIndex, newIndex)
            let end = max(anchorIndex, newIndex)
            let rangeItems = orderedItems[start...end]
            
            selectedItemIDs = Set(rangeItems.map(\.objectID))
            selectionCursorID = newItem.objectID // Update cursor to where we moved
            
        } else {
            // Normal navigation - reset anchor/cursor
            selectedItemIDs = [newItem.objectID]
            selectionAnchorID = newItem.objectID
            selectionCursorID = newItem.objectID
        }
    }
    
    // Track the "cursor" (the active end of the selection)
    private var selectionCursorID: NSManagedObjectID?

    @MainActor
    func paste(item: ClipItem, plainText: Bool) {
        guard !isPasting else { return }
        isPasting = true
        let effectivePlainText = plainText || userDefaults.bool(forKey: "alwaysPastePlainText")
        Task {
            await waitForOverlayToHide()
            defer {
                isPasting = false
                resetState()
            }
            try? clipItemStore.markItemUsed(objectID: item.objectID)
            do {
                try await pasteEngine.pasteItem(
                    item, format: effectivePlainText ? .plainText : .preserved)
                soundPlayer.play(.paste)
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Paste failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func pasteMultipleItems(_ items: [ClipItem], plainText: Bool) {
        guard !items.isEmpty else { return }

        let effectivePlainText = plainText || userDefaults.bool(forKey: "alwaysPastePlainText")
        if effectivePlainText || shouldPasteMultipleAsPlainText(items) {
            pasteMultipleItemsAsPlainText(items)
        } else {
            pasteMultipleItemsPreservingRepresentations(items)
        }
    }

    @MainActor
    func pasteMultipleItemsAsPlainText(_ items: [ClipItem]) {
        guard !isPasting, !items.isEmpty else { return }
        isPasting = true
        Task {
            await waitForOverlayToHide()
            defer {
                isPasting = false
                resetState()
            }
            let objectIDs = items.map { $0.objectID }
            try? clipItemStore.markItemsUsed(objectIDs: objectIDs)

            // Join plain text content with newlines
            let joinedText = items.compactMap { $0.plainTextContent ?? $0.primaryText }
                .joined(separator: "\n")

            guard !joinedText.isEmpty else {
                Logger.paste.warning("No plain text content available to paste")
                return
            }

            do {
                try await pasteEngine.pastePlainText(joinedText)
                soundPlayer.play(.paste)
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Multi-paste failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func pasteMultipleItemsPreservingRepresentations(_ items: [ClipItem]) {
        guard !isPasting, !items.isEmpty else { return }
        isPasting = true
        Task {
            await waitForOverlayToHide()
            defer {
                isPasting = false
                resetState()
            }
            let objectIDs = items.map { $0.objectID }
            try? clipItemStore.markItemsUsed(objectIDs: objectIDs)

            do {
                for (index, item) in items.enumerated() {
                    try await pasteEngine.pasteItem(item, format: .preserved)
                    if index < items.count - 1 {
                        try await Task.sleep(nanoseconds: 150_000_000)
                    }
                }
                soundPlayer.play(.paste)
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Multi-paste failed: \(error.localizedDescription)")
            }
        }
    }

    private func shouldPasteMultipleAsPlainText(_ items: [ClipItem]) -> Bool {
        items.allSatisfy { item in
            switch item.itemTypeValue {
            case .text, .richText, .url, .code, .color:
                return true
            case .image, .file, .mixed:
                return false
            }
        }
    }

    @MainActor
    func requestAccessibility() {
        permissionManager.requestAccessibility()
    }
    
    @MainActor
    func handleReturnKey(orderedItems: [ClipItem], isShiftPressed: Bool) {
        guard !selectedItemIDs.isEmpty else { return }
        
        // Get selected items in order
        let selectedItems = orderedItems.filter { selectedItemIDs.contains($0.objectID) }
        guard !selectedItems.isEmpty else { return }
        
        // If single item, paste normally; if multiple, choose plain-text vs preserved based on content
        if selectedItems.count == 1 {
            paste(item: selectedItems[0], plainText: isShiftPressed)
        } else {
            pasteMultipleItems(selectedItems, plainText: isShiftPressed)
        }
    }

    @MainActor
    func closeOverlayForSettings(completion: @escaping () -> Void) {
        closeOverlayForPaste(completion)
    }

    @MainActor
    private func waitForOverlayToHide() async {
        await withCheckedContinuation { continuation in
            closeOverlayForPaste {
                continuation.resume()
            }
        }
    }
}

// SAFETY: OverlayViewModel is UI-owned and only accessed on the main actor.
@MainActor
extension OverlayViewModel: @unchecked Sendable {}
