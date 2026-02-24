import CloudKit
import CoreData
import Foundation
import MartenCore
import Observation
import SwiftUI

@MainActor
@Observable
final class MartenWatchContainer {
    let persistenceController: PersistenceController
    let clipItemStore: ClipItemStore
    let commandService: WatchCommandService
    let queryService: WatchQueryService
    let lockStateStore: WatchPinboardLockStateStore
    let syncCoordinator: SyncCoordinator?

    private(set) var pinboards: [WatchPinboardSummary] = []
    private(set) var items: [WatchClipSummary] = []
    private(set) var isLoadingItems = false

    var selectedPinboardID: UUID? {
        didSet {
            persistSelectedPinboardID()
            scheduleRefresh(immediate: true)
        }
    }

    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            scheduleRefresh(immediate: false)
        }
    }

    var lastOperationErrorMessage: String?
    var syncErrorMessage: String?
    var shouldPresentSyncErrorAlert = false
    var isRunningSyncAction = false

    private let userDefaults: UserDefaults

    private var hasStarted = false
    private var refreshTask: Task<Void, Never>?

    convenience init(
        persistenceController: PersistenceController = .shared,
        clipItemStore: ClipItemStore? = nil,
        userDefaults: UserDefaults = UserDefaults(suiteName: WatchDefaults.appGroupIdentifier) ?? .standard
    ) {
        self.init(
            persistenceController: persistenceController,
            clipItemStore: clipItemStore,
            userDefaults: userDefaults,
            syncCoordinator: Self.makeSyncCoordinator(
                persistenceController: persistenceController,
                userDefaults: userDefaults
            )
        )
    }

    init(
        persistenceController: PersistenceController,
        clipItemStore: ClipItemStore? = nil,
        userDefaults: UserDefaults,
        syncCoordinator: SyncCoordinator?
    ) {
        self.persistenceController = persistenceController
        self.userDefaults = userDefaults
        WatchDefaults.register(userDefaults)

        let store = clipItemStore ?? ClipItemStore(persistence: persistenceController)
        self.clipItemStore = store
        self.queryService = WatchQueryService(store: store)
        self.commandService = WatchCommandService(
            store: store,
            persistenceController: persistenceController
        )
        self.lockStateStore = WatchPinboardLockStateStore(userDefaults: userDefaults)
        self.syncCoordinator = syncCoordinator

        if let selectedRaw = userDefaults.string(forKey: WatchDefaults.selectedPinboardIDKey),
            let selectedID = UUID(uuidString: selectedRaw)
        {
            self.selectedPinboardID = selectedID
        } else {
            self.selectedPinboardID = nil
        }

        self.syncCoordinator?.syncEnabled = true
        userDefaults.set(true, forKey: WatchDefaults.syncEnabledKey)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        ensureSystemPinboardExists()
        await maybeStartSync()
        await refresh()
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            ensureSystemPinboardExists()
            await maybeStartSync()
            await refresh()
        case .background:
            syncCoordinator?.stopSync()
        default:
            break
        }
    }

    func clearOperationError() {
        lastOperationErrorMessage = nil
    }

    func clearSyncError() {
        syncErrorMessage = nil
        shouldPresentSyncErrorAlert = false
    }

    var customPinboards: [WatchPinboardSummary] {
        pinboards.filter { !$0.isSystemMarten }
    }

    var selectedPinboard: WatchPinboardSummary? {
        guard let selectedPinboardID else { return nil }
        return customPinboards.first { $0.id == selectedPinboardID }
    }

    var selectedPinboardTitle: String {
        selectedPinboard?.name ?? "All"
    }

    var isSelectedPinboardAwaitingUnlock: Bool {
        guard let selectedPinboardID else { return false }
        return lockStateStore.isLocked(selectedPinboardID) && !lockStateStore.canAccess(selectedPinboardID)
    }

    func refresh() async {
        refreshTask?.cancel()
        isLoadingItems = true
        defer { isLoadingItems = false }

        do {
            let fetchedPinboards = try await queryService.pinboards()
            pinboards = fetchedPinboards

            reconcileSelectionIfNeeded()
            reconcileLockState()

            let fetchedItems = try await queryService.items(
                query: searchQuery,
                pinboardID: selectedPinboardID,
                limit: 100
            )
            items = visibleItems(from: fetchedItems)
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func unlockSelectedPinboard() async -> Bool {
        guard let selectedPinboard else { return true }
        guard isSelectedPinboardAwaitingUnlock else { return true }

        let unlocked = await lockStateStore.unlock(
            pinboardID: selectedPinboard.id,
            pinboardName: selectedPinboard.name
        )
        if !unlocked {
            lastOperationErrorMessage = "Unable to unlock pinboard."
            return false
        }

        await refresh()
        return true
    }

    @discardableResult
    func createTextItem(_ text: String) async -> Bool {
        do {
            try await commandService.createTextItem(text)
            await refresh()
            return true
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func markItemUsed(itemID: UUID) async -> Bool {
        do {
            try await commandService.markItemUsed(itemID: itemID)
            await refresh()
            return true
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func togglePin(itemID: UUID) async -> Bool {
        do {
            try await commandService.togglePin(itemID: itemID)
            await refresh()
            return true
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateTextItem(itemID: UUID, newText: String) async -> Bool {
        do {
            try await commandService.updateTextItem(itemID: itemID, newText: newText)
            await refresh()
            return true
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func moveItem(itemID: UUID, to pinboardID: UUID) async -> Bool {
        do {
            try await commandService.moveItem(itemID: itemID, toPinboardID: pinboardID)
            await refresh()
            return true
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteItem(itemID: UUID) async -> Bool {
        do {
            try await commandService.deleteItem(itemID: itemID)
            await refresh()
            return true
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    func triggerSyncNow() async {
        guard let syncCoordinator else {
            syncErrorMessage = "iCloud sync is unavailable in this build."
            shouldPresentSyncErrorAlert = true
            return
        }

        isRunningSyncAction = true
        defer { isRunningSyncAction = false }

        do {
            try await syncCoordinator.triggerSyncNow()
            clearSyncError()
            await refresh()
        } catch {
            syncErrorMessage = error.localizedDescription
            shouldPresentSyncErrorAlert = true
        }
    }

    func handleCloudKitPushNotification() async {
        guard let syncCoordinator else { return }
        guard syncCoordinator.syncEnabled else { return }

        do {
            try await syncCoordinator.startSync()
            clearSyncError()
        } catch {
            syncErrorMessage = error.localizedDescription
            shouldPresentSyncErrorAlert = true
            return
        }

        await syncCoordinator.handlePushNotification()
        await refresh()
    }

    func selectPinboard(_ pinboardID: UUID?) {
        guard selectedPinboardID != pinboardID else { return }
        selectedPinboardID = pinboardID
    }

    private func scheduleRefresh(immediate: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private func persistSelectedPinboardID() {
        if let selectedPinboardID {
            userDefaults.set(selectedPinboardID.uuidString, forKey: WatchDefaults.selectedPinboardIDKey)
        } else {
            userDefaults.removeObject(forKey: WatchDefaults.selectedPinboardIDKey)
        }
    }

    private func reconcileSelectionIfNeeded() {
        guard let selectedPinboardID else { return }
        let validIDs = Set(customPinboards.map(\.id))
        if !validIDs.contains(selectedPinboardID) {
            self.selectedPinboardID = nil
        }
    }

    private func reconcileLockState() {
        let lockableIDs = Set(customPinboards.filter { !$0.isShared }.map(\.id))
        lockStateStore.reconcile(validPinboardIDs: lockableIDs)
    }

    private func visibleItems(from source: [WatchClipSummary]) -> [WatchClipSummary] {
        guard !isSelectedPinboardAwaitingUnlock else {
            return []
        }

        let customPinboardIDs = Set(customPinboards.map(\.id))

        if let selectedPinboardID {
            return source.filter { $0.pinboardIDs.contains(selectedPinboardID) }
        }

        return source.filter { item in
            let assignedCustomIDs = item.pinboardIDs.filter { customPinboardIDs.contains($0) }
            if assignedCustomIDs.isEmpty {
                return true
            }

            return !assignedCustomIDs.contains {
                lockStateStore.isLocked($0) && !lockStateStore.canAccess($0)
            }
        }
    }

    private func ensureSystemPinboardExists() {
        let context = persistenceController.newBackgroundContext()
        let survivingID: UUID?
        let removedIDs: Set<UUID>
        do {
            (survivingID, removedIDs) = try SystemPinboardBootstrapper().ensureSystemPinboard(in: context)
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return
        }

        if let selectedPinboardID, removedIDs.contains(selectedPinboardID) {
            self.selectedPinboardID = survivingID
        }
    }

    private func maybeStartSync() async {
        guard let syncCoordinator else { return }

        syncCoordinator.syncEnabled = true
        userDefaults.set(true, forKey: WatchDefaults.syncEnabledKey)

        do {
            try await syncCoordinator.startSync()
            clearSyncError()
        } catch {
            syncErrorMessage = error.localizedDescription
            shouldPresentSyncErrorAlert = false
        }
    }

    private static func makeSyncCoordinator(
        persistenceController: PersistenceController,
        userDefaults: UserDefaults
    ) -> SyncCoordinator? {
        let cloudKitConfiguration = CloudKitConfiguration.default
        let appGroupIdentifier = WatchDefaults.appGroupIdentifier

        let syncCoordinator = SyncCoordinator.create(
            cloudKitConfiguration: cloudKitConfiguration,
            persistenceController: persistenceController,
            userDefaults: userDefaults,
            syncEnabledProvider: {
                let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
                return defaults.bool(forKey: WatchDefaults.syncEnabledKey)
            }
        )

        syncCoordinator.syncEnabled = true
        userDefaults.set(true, forKey: WatchDefaults.syncEnabledKey)

        return syncCoordinator
    }
}
