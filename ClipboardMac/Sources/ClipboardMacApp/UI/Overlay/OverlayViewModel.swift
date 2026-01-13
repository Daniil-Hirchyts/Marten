import ClipboardCore
import ClipboardMacServices
import CoreData
import Foundation
import OSLog

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var mode: OverlayMode = .browse
    @Published var selectedItemIDs: Set<NSManagedObjectID> = []
    @Published var showAccessibilityAlert = false
    @Published var isPasting = false

    private let stackStore: StackSessionStore
    private let clipItemStore: ClipItemStore
    private let pasteEngine: PasteEngine
    private let permissionManager: PermissionManager
    private let closeOverlay: () -> Void
    private let soundPlayer = SoundEffectPlayer()

    private var stackSession: StackSession?

    init(
        persistence: PersistenceController,
        pasteEngine: PasteEngine,
        permissionManager: PermissionManager,
        closeOverlay: @escaping () -> Void
    ) {
        self.stackStore = StackSessionStore(persistence: persistence)
        self.clipItemStore = ClipItemStore(persistence: persistence)
        self.pasteEngine = pasteEngine
        self.permissionManager = permissionManager
        self.closeOverlay = closeOverlay
    }

    func setMode(_ mode: OverlayMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        selectedItemIDs.removeAll()
        switch mode {
        case .browse:
            if let stackSession {
                try? stackStore.deleteSession(sessionID: stackSession.objectID)
            }
            stackSession = nil
        case .pasteStack:
            stackSession = try? stackStore.createSession()
        }
    }

    func resetState() {
        selectedItemIDs.removeAll()
        if let stackSession {
            try? stackStore.deleteSession(sessionID: stackSession.objectID)
        }
        stackSession = nil
        mode = .browse
    }

    func isSelected(_ item: ClipItem) -> Bool {
        selectedItemIDs.contains(item.objectID)
    }

    func selectItem(_ item: ClipItem, in orderedItems: [ClipItem], isShiftPressed: Bool, isCommandPressed: Bool) {
        if isShiftPressed {
            // Range selection
            guard let lastSelectedID = selectedItemIDs.first, // Simplification: Anchor to an arbitrary selection
                  let anchorIndex = orderedItems.firstIndex(where: { $0.objectID == lastSelectedID }),
                  let currentIndex = orderedItems.firstIndex(where: { $0.objectID == item.objectID }) else {
                selectedItemIDs = [item.objectID]
                return
            }
            
            let start = min(anchorIndex, currentIndex)
            let end = max(anchorIndex, currentIndex)
            
            // In a real range selection, we'd typically add to existing or replace. 
            // Standard Finder behavior: Shift+Click extends selection from anchor. 
            // For simplicity here, we'll union the new range with existing.
            let rangeIDs = orderedItems[start...end].map { $0.objectID }
            selectedItemIDs.formUnion(rangeIDs)
            
        } else if isCommandPressed {
            // Toggle selection
            if selectedItemIDs.contains(item.objectID) {
                selectedItemIDs.remove(item.objectID)
            } else {
                selectedItemIDs.insert(item.objectID)
            }
        } else {
            // Single selection (replace or deselect)
            if selectedItemIDs.count == 1 && selectedItemIDs.contains(item.objectID) {
                selectedItemIDs.removeAll()
            } else {
                selectedItemIDs = [item.objectID]
            }
        }
        
        if mode == .pasteStack {
            syncStackEntries(using: orderedItems)
        }
    }

    func selectAll(in orderedItems: [ClipItem]) {
        guard mode == .pasteStack else { return }
        selectedItemIDs = Set(orderedItems.map { $0.objectID })
        syncStackEntries(using: orderedItems)
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
        if let stackSession {
            try? stackStore.clearEntries(sessionID: stackSession.objectID)
        }
    }

    func restoreSelection(_ ids: Set<NSManagedObjectID>, in orderedItems: [ClipItem]) {
        selectedItemIDs = ids
        if mode == .pasteStack {
            syncStackEntries(using: orderedItems)
        }
    }

    func paste(item: ClipItem, plainText: Bool) {
        isPasting = true
        Task {
            defer { isPasting = false }
            try? clipItemStore.markItemUsed(objectID: item.objectID)
            do {
                try await pasteEngine.pasteItem(item, format: plainText ? .plainText : .preserved)
                soundPlayer.play(.paste)
                closeOverlay()
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Paste failed: \(error.localizedDescription)")
            }
        }
    }

    func pasteStack(plainText: Bool) {
        guard let stackSession else { return }
        isPasting = true
        Task {
            defer { isPasting = false }
            let orderedIDs = stackSession.entries?
                .sorted { $0.position < $1.position }
                .compactMap { $0.clipItem?.objectID } ?? []
            try? clipItemStore.markItemsUsed(objectIDs: orderedIDs)
            do {
                try await pasteEngine.pasteStack(stackSession, format: plainText ? .plainText : .preserved)
                soundPlayer.play(.paste)
                closeOverlay()
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Paste stack failed: \(error.localizedDescription)")
            }
        }
    }

    func requestAccessibility() {
        permissionManager.requestAccessibility()
    }

    private func syncStackEntries(using orderedItems: [ClipItem]) {
        guard let stackSession else { return }
        let orderedIDs = orderedItems
            .filter { selectedItemIDs.contains($0.objectID) }
            .map { $0.objectID }
        do {
            try stackStore.setEntries(sessionID: stackSession.objectID, clipItemIDs: orderedIDs)
        } catch {
            Logger.paste.error("Failed to sync stack entries: \(error.localizedDescription)")
        }
    }
}
