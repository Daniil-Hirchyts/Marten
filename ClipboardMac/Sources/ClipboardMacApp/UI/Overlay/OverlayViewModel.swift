import ClipboardCore
import ClipboardMacServices
import CoreData
import Foundation
import OSLog

final class OverlayViewModel: ObservableObject {
    @MainActor @Published var mode: OverlayMode = .browse
    @MainActor @Published var selectedItemIDs: Set<NSManagedObjectID> = []
    @MainActor @Published var showAccessibilityAlert = false
    @MainActor @Published var isPasting = false
    @MainActor @Published var syncError: Error?

    private let stackStore: StackSessionStore
    private let clipItemStore: ClipItemStore
    private let pasteEngine: any PasteEngineProtocol
    private let permissionManager: PermissionManager
    private let closeOverlayForPaste: (@escaping () -> Void) -> Void
    private let soundPlayer = SoundEffectPlayer()
    private let selectionHandler = ItemSelectionHandler()

    private let stackSyncQueue = DispatchQueue(
        label: "paste.overlay.stackSync", qos: .userInitiated)
    private let stackSyncDebounce: TimeInterval = 0.02
    private var pendingStackSyncWorkItem: DispatchWorkItem?
    private var lastRequestedStackSync:
        (sessionID: NSManagedObjectID, orderedClipItemIDs: [NSManagedObjectID])?
    private let shouldProfileSelectionLatency =
        ProcessInfo.processInfo.environment["PASTE_PROFILE_SELECTION_LATENCY"] == "1"

    private var stackSession: StackSession?

    init(
        persistence: PersistenceController,
        pasteEngine: any PasteEngineProtocol,
        permissionManager: PermissionManager,
        closeOverlayForPaste: @escaping (@escaping () -> Void) -> Void
    ) {
        self.stackStore = StackSessionStore(persistence: persistence)
        self.clipItemStore = ClipItemStore(persistence: persistence)
        self.pasteEngine = pasteEngine
        self.permissionManager = permissionManager
        self.closeOverlayForPaste = closeOverlayForPaste
    }

    @MainActor
    convenience init(
        services: any AppServiceProviding,
        closeOverlayForPaste: @escaping (@escaping () -> Void) -> Void
    ) {
        self.init(
            persistence: services.persistence,
            pasteEngine: services.pasteEngine,
            permissionManager: services.permissionManager,
            closeOverlayForPaste: closeOverlayForPaste
        )
    }

    @MainActor
    func setMode(_ mode: OverlayMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        selectedItemIDs.removeAll()
        cancelPendingStackSync()
        switch mode {
        case .browse:
            if let stackSession {
                let sessionID = stackSession.objectID
                stackSyncQueue.async { [stackStore] in
                    try? stackStore.deleteSession(sessionID: sessionID)
                }
            }
            stackSession = nil
        case .pasteStack:
            stackSession = try? stackStore.createSession()
        }
    }

    @MainActor
    func resetState() {
        selectedItemIDs.removeAll()
        cancelPendingStackSync()
        if let stackSession {
            let sessionID = stackSession.objectID
            stackSyncQueue.async { [stackStore] in
                try? stackStore.deleteSession(sessionID: sessionID)
            }
        }
        stackSession = nil
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

        if mode == .pasteStack {
            scheduleStackSync(using: orderedItems)
        }
    }

    @MainActor
    func selectAll(in orderedItems: [ClipItem]) {
        guard mode == .pasteStack else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        selectedItemIDs = Set(orderedItems.map { $0.objectID })
        if shouldProfileSelectionLatency {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            Logger.paste.debug("Selection update (selectAll) took \(elapsedMs, privacy: .public)ms")
        }
        scheduleStackSync(using: orderedItems)
    }

    @MainActor
    func clearSelection() {
        selectedItemIDs.removeAll()
        guard mode == .pasteStack else { return }
        scheduleStackSyncToEmptySelection()
    }

    @MainActor
    func restoreSelection(_ ids: Set<NSManagedObjectID>, in orderedItems: [ClipItem]) {
        selectedItemIDs = ids
        if mode == .pasteStack {
            scheduleStackSync(using: orderedItems)
        }
    }

    @MainActor
    func paste(item: ClipItem, plainText: Bool) {
        guard !isPasting else { return }
        isPasting = true
        Task {
            await waitForOverlayToHide()
            defer {
                isPasting = false
                resetState()
            }
            try? clipItemStore.markItemUsed(objectID: item.objectID)
            do {
                try await pasteEngine.pasteItem(item, format: plainText ? .plainText : .preserved)
                soundPlayer.play(.paste)
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Paste failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func pasteStack(plainText: Bool) {
        guard let stackSession else { return }
        guard !isPasting else { return }
        isPasting = true
        Task {
            await waitForOverlayToHide()
            await flushPendingStackSync()
            defer {
                isPasting = false
                resetState()
            }
            let orderedIDs =
                stackSession.entries?
                .sorted { $0.position < $1.position }
                .compactMap { $0.clipItem?.objectID } ?? []
            try? clipItemStore.markItemsUsed(objectIDs: orderedIDs)
            do {
                try await pasteEngine.pasteStack(
                    stackSession, format: plainText ? .plainText : .preserved)
                soundPlayer.play(.paste)
            } catch PasteEngineError.accessibilityPermissionDenied {
                showAccessibilityAlert = true
            } catch {
                Logger.paste.error("Paste stack failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func requestAccessibility() {
        permissionManager.requestAccessibility()
    }

    @MainActor
    private func waitForOverlayToHide() async {
        await withCheckedContinuation { continuation in
            closeOverlayForPaste {
                continuation.resume()
            }
        }
    }

    @MainActor
    private func scheduleStackSync(using orderedItems: [ClipItem]) {
        guard mode == .pasteStack, let stackSession else { return }

        let sessionID = stackSession.objectID
        let selectionSnapshot = selectedItemIDs
        let orderedIDs =
            orderedItems
            .filter { selectionSnapshot.contains($0.objectID) }
            .map { $0.objectID }

        lastRequestedStackSync = (sessionID: sessionID, orderedClipItemIDs: orderedIDs)

        pendingStackSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performStackSync(sessionID: sessionID, orderedClipItemIDs: orderedIDs)
        }
        pendingStackSyncWorkItem = workItem
        stackSyncQueue.asyncAfter(deadline: .now() + stackSyncDebounce, execute: workItem)
    }

    @MainActor
    private func scheduleStackSyncToEmptySelection() {
        guard let stackSession else { return }
        let sessionID = stackSession.objectID
        lastRequestedStackSync = (sessionID: sessionID, orderedClipItemIDs: [])

        pendingStackSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performStackSync(sessionID: sessionID, orderedClipItemIDs: [])
        }
        pendingStackSyncWorkItem = workItem
        stackSyncQueue.asyncAfter(deadline: .now() + stackSyncDebounce, execute: workItem)
    }

    private func performStackSync(
        sessionID: NSManagedObjectID, orderedClipItemIDs: [NSManagedObjectID]
    ) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        var syncSucceeded = false
        var capturedError: Error?
        do {
            try stackStore.setEntries(sessionID: sessionID, clipItemIDs: orderedClipItemIDs)
            syncSucceeded = true
        } catch {
            capturedError = error
        }

        if shouldProfileSelectionLatency {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            Logger.paste.debug(
                "Stack selection sync took \(elapsedMs, privacy: .public)ms for \(orderedClipItemIDs.count, privacy: .public) items"
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.stackSession?.objectID == sessionID else { return }
            if syncSucceeded {
                self.syncError = nil
            } else {
                self.syncError = capturedError
                if let capturedError {
                    Logger.paste.error(
                        "Failed to sync stack entries: \(capturedError.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    private func cancelPendingStackSync() {
        pendingStackSyncWorkItem?.cancel()
        pendingStackSyncWorkItem = nil
        lastRequestedStackSync = nil
    }

    @MainActor
    private func flushPendingStackSync() async {
        pendingStackSyncWorkItem?.cancel()
        pendingStackSyncWorkItem = nil
        guard let request = lastRequestedStackSync else { return }
        await withCheckedContinuation { continuation in
            stackSyncQueue.async { [weak self] in
                self?.performStackSync(
                    sessionID: request.sessionID, orderedClipItemIDs: request.orderedClipItemIDs)
                continuation.resume()
            }
        }
    }
}
