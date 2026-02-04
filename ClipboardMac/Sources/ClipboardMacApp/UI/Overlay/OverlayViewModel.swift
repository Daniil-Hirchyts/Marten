@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
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

    private let shouldProfileSelectionLatency =
        ProcessInfo.processInfo.environment["PASTE_PROFILE_SELECTION_LATENCY"] == "1"

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
        let startedAt = CFAbsoluteTimeGetCurrent()
        selectedItemIDs = selectionHandler.updatedSelection(
            currentSelection: selectedItemIDs,
            orderedItems: orderedItems,
            tappedItem: item,
            isShiftPressed: isShiftPressed,
            isCommandPressed: isCommandPressed
        )

        if shouldProfileSelectionLatency {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            Logger.paste.debug("Selection update took \(elapsedMs, privacy: .public)ms")
        }
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
    func requestAccessibility() {
        permissionManager.requestAccessibility()
    }
    
    @MainActor
    func handleReturnKey(orderedItems: [ClipItem], isShiftPressed: Bool) {
        guard !selectedItemIDs.isEmpty else { return }
        
        // Get selected items in order
        let selectedItems = orderedItems.filter { selectedItemIDs.contains($0.objectID) }
        guard !selectedItems.isEmpty else { return }
        
        // If single item, paste normally; if multiple, paste as plain text
        if selectedItems.count == 1 {
            paste(item: selectedItems[0], plainText: isShiftPressed)
        } else {
            pasteMultipleItemsAsPlainText(selectedItems)
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
