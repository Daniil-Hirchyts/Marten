import CloudKit
import CoreData
import Foundation
import MartenCore
import SwiftUI
#if os(iOS)
private let watchBridge = WatchConnectivityBridge.shared
#endif

@MainActor
@Observable
public final class MartenIOSAppContainer {
    public let persistenceController: PersistenceController
    public let clipItemStore: ClipItemStore
    public let commandService: ClipItemCommandService
    public let linkPreviewCoordinator: LinkPreviewCoordinator
    public let lockStateStore: PinboardLockStateStore
    public let syncCoordinator: SyncCoordinator?
    public let sharingRepository: (any PinboardSharingRepositoryProtocol)?
    public let appleIntelligence: any AppleIntelligenceTextTransforming

    public var selectedTab: MartenIOSTab = .dashboard
    public var selectedPinboardID: UUID?
    public var pendingWidgetAction: WidgetAction?
    public var dashboardRefreshRevision: UInt64 = 0

    public enum WidgetAction: Equatable {
        case search
        case paste
        case create
    }
    public var shouldShowIntegrationsOnboarding: Bool {
        didSet {
            userDefaults.set(
                shouldShowIntegrationsOnboarding,
                forKey: MartenIOSDefaults.showIntegrationsOnboardingKey
            )
        }
    }
    public var showDuringScreenSharing: Bool {
        didSet {
            userDefaults.set(
                showDuringScreenSharing,
                forKey: "settings.toggle.showDuringScreenSharing"
            )
        }
    }
    public var appearance: MartenIOSAppearance {
        didSet {
            userDefaults.set(appearance.rawValue, forKey: MartenIOSDefaults.appearanceKey)
        }
    }
    public var lastOperationErrorMessage: String?
    public var syncErrorMessage: String?
    public var isRunningSyncAction = false

    public var preferredColorScheme: ColorScheme? {
        appearance.preferredColorScheme
    }

    private let userDefaults: UserDefaults
    private let clipboardReader: any ClipboardReading
    private let clipboardPayloadBuilder: ClipboardPayloadBuilder
    private let syncConfigurationProvider: any MartenIOSSyncConfigurationProviding

    private var hasStarted = false
    private var lastSeenShareExtensionSuccessAt: Double
    private var lastSeenKeyboardMutationAt: Double

    public convenience init(
        persistenceController: PersistenceController = .shared,
        clipItemStore: ClipItemStore? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.init(
            persistenceController: persistenceController,
            clipItemStore: clipItemStore,
            userDefaults: userDefaults,
            clipboardReader: SystemClipboardReader(),
            clipboardPayloadBuilder: ClipboardPayloadBuilder(),
            linkPreviewFetcher: LinkPreviewFetcher(),
            syncConfigurationProvider: MartenIOSSyncConfigurationProvider(),
            appleIntelligence: AppleIntelligenceTextService()
        )
    }

    init(
        persistenceController: PersistenceController = .shared,
        clipItemStore: ClipItemStore? = nil,
        userDefaults: UserDefaults = .standard,
        clipboardReader: any ClipboardReading = SystemClipboardReader(),
        clipboardPayloadBuilder: ClipboardPayloadBuilder = ClipboardPayloadBuilder(),
        linkPreviewFetcher: any LinkPreviewFetching = LinkPreviewFetcher(),
        syncConfigurationProvider: any MartenIOSSyncConfigurationProviding =
            MartenIOSSyncConfigurationProvider(),
        sharingRepository: (any PinboardSharingRepositoryProtocol)? = nil,
        appleIntelligence: any AppleIntelligenceTextTransforming = AppleIntelligenceTextService()
    ) {
        self.persistenceController = persistenceController
        self.userDefaults = userDefaults
        self.clipboardReader = clipboardReader
        self.clipboardPayloadBuilder = clipboardPayloadBuilder
        self.syncConfigurationProvider = syncConfigurationProvider
        self.appleIntelligence = appleIntelligence

        MartenIOSDefaults.registerDefaults(userDefaults)
        if let appGroupDefaults = UserDefaults(suiteName: "group.com.hirchyts.marten") {
            SharedPinboardsFeatureFlag.registerDefaults(appGroupDefaults)
        }
        self.lastSeenShareExtensionSuccessAt = userDefaults.double(
            forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey
        )
        self.lastSeenKeyboardMutationAt = userDefaults.double(
            forKey: MartenIOSDefaults.keyboardLastMutationAtKey
        )

        let resolvedStore = clipItemStore ?? ClipItemStore(persistence: persistenceController)
        self.clipItemStore = resolvedStore
        self.commandService = ClipItemCommandService(store: resolvedStore)
        self.linkPreviewCoordinator = LinkPreviewCoordinator(
            store: resolvedStore,
            fetcher: linkPreviewFetcher
        )
        let resolvedLockStateStore = PinboardLockStateStore(userDefaults: userDefaults)
        self.lockStateStore = resolvedLockStateStore

        let appearanceRawValue = userDefaults.string(forKey: MartenIOSDefaults.appearanceKey) ?? ""
        self.appearance = MartenIOSAppearance(rawValue: appearanceRawValue) ?? .system

        if let selectedRaw = userDefaults.string(forKey: MartenIOSDefaults.selectedPinboardIDKey),
            let selectedUUID = UUID(uuidString: selectedRaw)
        {
            self.selectedPinboardID = selectedUUID
        } else {
            self.selectedPinboardID = nil
        }
        self.shouldShowIntegrationsOnboarding = userDefaults.bool(
            forKey: MartenIOSDefaults.showIntegrationsOnboardingKey
        )
        // Default to true if not set, to match Mac app default
        self.showDuringScreenSharing = userDefaults.object(forKey: "settings.toggle.showDuringScreenSharing") as? Bool ?? true

        self.syncCoordinator = AppCoordinatorFactory.makeSyncCoordinator(
            persistenceController: persistenceController,
            userDefaults: userDefaults,
            syncConfigurationProvider: syncConfigurationProvider
        )
        self.sharingRepository =
            sharingRepository
            ?? AppCoordinatorFactory.makeSharingRepository(
                persistenceController: persistenceController,
                userDefaults: userDefaults,
                syncConfigurationProvider: syncConfigurationProvider,
                isPinboardLocked: { pinboardID in
                    resolvedLockStateStore.isLocked(pinboardID)
                }
            )
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        ensureSystemPinboardExists()
        await maybeStartSyncIfEnabled()
        ensureSystemPinboardExists()
        await reconcileShareMetadataFromTokens()
        reconcileLockStateForShareMembership()
        await refreshPendingLinkPreviews()
    }

    public func setSelectedPinboardID(_ pinboardID: UUID?) {
        if let pinboardID, isSelectablePinboard(pinboardID) {
            selectedPinboardID = pinboardID
        } else {
            selectedPinboardID = nil
        }

        if let pinboardID {
            if selectedPinboardID == pinboardID {
                userDefaults.set(
                    pinboardID.uuidString, forKey: MartenIOSDefaults.selectedPinboardIDKey)
            } else {
                userDefaults.removeObject(forKey: MartenIOSDefaults.selectedPinboardIDKey)
            }
        } else {
            userDefaults.removeObject(forKey: MartenIOSDefaults.selectedPinboardIDKey)
        }
    }

    public func setAppearance(_ appearance: MartenIOSAppearance) {
        self.appearance = appearance
    }

    public func clearErrorMessage() {
        lastOperationErrorMessage = nil
    }

    public func clearSyncError() {
        syncErrorMessage = nil
    }

    public func canOpenShareSettings(for pinboard: Pinboard) -> Bool {
        guard !(lockStateStore.isLocked(pinboard.id) && !pinboard.isShared) else {
            lastOperationErrorMessage = PinboardSharingError.cannotShareLockedPinboard.localizedDescription
            return false
        }
        return true
    }

    public func setPinboardLock(_ enabled: Bool, for pinboard: Pinboard) {
        if enabled && pinboard.isShared {
            lockStateStore.setLock(false, for: pinboard.id)
            lastOperationErrorMessage = PinboardSharingError.cannotLockSharedPinboard.localizedDescription
            return
        }

        lockStateStore.setLock(enabled, for: pinboard.id)
    }

    public func lockPinboardNow(_ pinboard: Pinboard) {
        guard !pinboard.isShared else {
            lockStateStore.setLock(false, for: pinboard.id)
            lastOperationErrorMessage = PinboardSharingError.cannotLockSharedPinboard.localizedDescription
            return
        }

        lockStateStore.lockNow(pinboardID: pinboard.id)
    }

    public func openIntegrationsSettings() {
        selectedTab = .settings
        dismissIntegrationsOnboarding()
    }

    public func dismissIntegrationsOnboarding() {
        shouldShowIntegrationsOnboarding = false
    }

    public func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            ensureSystemPinboardExists()
            await maybeStartSyncIfEnabled()
            syncCoordinator?.handleAppDidBecomeActive()
            ensureSystemPinboardExists()
            await reconcileShareMetadataFromTokens()
            reconcileLockStateForShareMembership()
            await refreshPendingLinkPreviews()
            refreshDashboardStateFromShareExtensionIfNeeded()
            await autoSaveFromClipboardIfNeeded()
        case .background:
            syncCoordinator?.handleAppWillResignActive()
        default:
            break
        }
    }

    public func setSyncEnabled(_ enabled: Bool) async {
        guard let syncCoordinator else { return }

        syncCoordinator.syncEnabled = enabled
        userDefaults.set(enabled, forKey: MartenIOSDefaults.syncEnabledKey)

        if enabled {
            await maybeStartSyncIfEnabled()
        } else {
            syncCoordinator.stopSync()
        }
    }

    public func triggerSyncNow() async {
        guard let syncCoordinator else { return }

        isRunningSyncAction = true
        defer { isRunningSyncAction = false }

        do {
            try await syncCoordinator.triggerSyncNow()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    public func handleCloudKitPushNotification() async {
        guard let syncCoordinator else { return }
        guard syncCoordinator.syncEnabled else { return }

        do {
            try await syncCoordinator.startSync()
        } catch {
            syncErrorMessage = error.localizedDescription
            return
        }

        await syncCoordinator.handlePushNotification()
        await refreshPendingLinkPreviews()
        #if os(iOS)
        watchBridge.notifyWatchSyncCompleted()
        watchBridge.pushLockState(lockStateStore.lockedPinboardIDs)
        #endif
    }

    public func refreshPendingLinkPreviews() async {
        await linkPreviewCoordinator.fetchPending(limit: 25)
    }

    public func createTextItem(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await performMutation {
            try await commandService.createTextItem(
                text: trimmed,
                sourceApp: sourceAppInfo(),
                isUserCreated: true
            )
        }
    }

    public func createRichTextItem(plainText: String, rtfData: Data) async {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await performMutation {
            let payload = ClipItemPayload(
                representations: [
                    .plainText(trimmed, displayOrder: 0),
                    ClipRepresentationPayload(
                        kind: .rtf,
                        uti: "public.rtf",
                        data: rtfData,
                        fileExtension: "rtf",
                        displayOrder: 1
                    ),
                ],
                primaryText: trimmed,
                itemType: .text
            )
            try await commandService.createItem(
                payload: payload,
                sourceApp: sourceAppInfo(),
                isUserCreated: true
            )
        }
    }

    public func createItemFromClipboard() async {
        guard let content = clipboardReader.readContent() else {
            lastOperationErrorMessage = "Clipboard is empty or unsupported."
            return
        }

        guard let payload = clipboardPayloadBuilder.buildPayload(from: content) else {
            lastOperationErrorMessage = "Clipboard content could not be saved."
            return
        }

        do {
            try await commandService.createItem(
                payload: payload,
                sourceApp: sourceAppInfo(),
                isUserCreated: true
            )
            if payload.needsLinkPreview {
                await refreshPendingLinkPreviews()
            }
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    private func autoSaveFromClipboardIfNeeded() async {
        #if canImport(UIKit)
        let pasteboard = UIPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        let lastChangeCount = userDefaults.integer(forKey: MartenIOSDefaults.lastPasteboardChangeCountKey)
        
        guard currentChangeCount != lastChangeCount else {
            return
        }
        
        // Update the stored count so we don't prompt again unnecessarily
        userDefaults.set(currentChangeCount, forKey: MartenIOSDefaults.lastPasteboardChangeCountKey)
        
        // Only attempt to read and save if something meaningful is there
        if pasteboard.hasStrings || pasteboard.hasImages || pasteboard.hasURLs {
            await createItemFromClipboard()
        }
        #endif
    }

    public func createScannedPages(_ pageJPEGData: [Data]) async {
        guard !pageJPEGData.isEmpty else { return }

        await performMutation {
            for pageData in pageJPEGData where !pageData.isEmpty {
                let payload = ClipItemPayload(
                    representations: [
                        ClipRepresentationPayload(
                            kind: .jpeg,
                            uti: "public.jpeg",
                            data: pageData,
                            fileExtension: "jpg",
                            displayOrder: 0
                        )
                    ],
                    primaryText: "Scanned Document",
                    itemType: .image
                )
                try await commandService.createItem(
                    payload: payload,
                    sourceApp: sourceAppInfo(),
                    isUserCreated: true
                )
            }
        }
    }

    public func createPinboard(name: String, colorHex: String, iconName: String?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastOperationErrorMessage = "Pinboard name cannot be empty."
            return
        }

        await performMutation {
            try await commandService.createPinboard(
                name: trimmed,
                colorHex: colorHex,
                iconName: iconName
            )
        }
    }

    public func updatePinboard(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastOperationErrorMessage = "Pinboard name cannot be empty."
            return
        }

        await performMutation {
            try await commandService.updatePinboard(
                objectID: objectID,
                name: trimmed,
                colorHex: colorHex,
                iconName: iconName
            )
        }
    }

    public func deletePinboard(_ pinboard: Pinboard) async {
        guard !pinboard.isSystemMarten else {
            lastOperationErrorMessage = "Clipboard History pinboard cannot be deleted."
            return
        }

        if pinboard.isShared {
            guard let sharingRepository else {
                lastOperationErrorMessage = "Sharing is unavailable in this build."
                return
            }

            do {
                if pinboard.shareRole == .owner {
                    try await sharingRepository.stopSharing(pinboardID: pinboard.objectID)
                } else {
                    try await sharingRepository.leaveShare(pinboardID: pinboard.objectID)
                }
                reconcileLockStateForShareMembership()
                if selectedPinboardID == pinboard.id {
                    setSelectedPinboardID(nil)
                }
            } catch {
                lastOperationErrorMessage = error.localizedDescription
                return
            }
        } else {
            do {
                try await commandService.deletePinboard(objectID: pinboard.objectID)
            } catch {
                lastOperationErrorMessage = error.localizedDescription
                return
            }
            if selectedPinboardID == pinboard.id {
                setSelectedPinboardID(nil)
            }
        }

        await forceCloudConvergenceAfterPinboardMutation()
        invalidateDashboardItems()
    }

    public func moveItems(
        _ objectIDs: [NSManagedObjectID], toPinboardID pinboardID: NSManagedObjectID
    )
        async
    {
        guard !objectIDs.isEmpty else { return }

        await performMutation {
            try await commandService.moveItems(
                objectIDs: objectIDs,
                toPinboardID: pinboardID
            )
            invalidateDashboardItems()
        }
    }

    public func moveItemsToAll(_ objectIDs: [NSManagedObjectID]) async {
        guard !objectIDs.isEmpty else { return }

        do {
            let viewContext = persistenceController.viewContext
            let removalsByPinboardID: [NSManagedObjectID: [NSManagedObjectID]] =
                try viewContext
                .performAndWaitThrowing {
                    var mapping: [NSManagedObjectID: [NSManagedObjectID]] = [:]

                    for objectID in objectIDs {
                        guard
                            let item = try? viewContext.existingObject(with: objectID) as? ClipItem
                        else {
                            continue
                        }

                        let pinboards = item.pinboards?.filter { !$0.isSystemMarten } ?? []
                        for pinboard in pinboards {
                            mapping[pinboard.objectID, default: []].append(item.objectID)
                        }
                    }

                    return mapping
                }

            for (pinboardID, itemObjectIDs) in removalsByPinboardID {
                try await commandService.removeItems(
                    objectIDs: itemObjectIDs,
                    fromPinboardID: pinboardID
                )
            }

            invalidateDashboardItems()
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func deleteItems(_ objectIDs: [NSManagedObjectID]) async {
        guard !objectIDs.isEmpty else { return }
        await performMutation { try await commandService.deleteItems(objectIDs: objectIDs) }
    }

    public func deleteAllData() async {
        await performMutation { try await commandService.deleteAllItems() }
        invalidateDashboardItems()
        setSelectedPinboardID(nil)
    }

    public func nukeAllData() async {
        if let syncCoordinator {
            let result = await syncCoordinator.wipeEverything()
            if let summary = result.failureSummary {
                lastOperationErrorMessage = summary
            }
        } else {
            await performMutation { try await commandService.deleteAllItems() }
        }

        invalidateDashboardItems()
        setSelectedPinboardID(nil)
        reconcileLockStateForShareMembership()
    }

    public func deleteDataCreatedOnThisDevice() async {
        await performMutation { try await commandService.deleteItemsFromThisDevice() }
        invalidateDashboardItems()
    }

    public func deleteOnlyPinboards() async {
        if let sharingRepository {
            let shareRefs = sharedPinboardReferencesForBulkDelete()
            for reference in shareRefs {
                do {
                    if reference.isOwner {
                        try await sharingRepository.stopSharing(pinboardID: reference.objectID)
                    } else {
                        try await sharingRepository.leaveShare(pinboardID: reference.objectID)
                    }
                } catch {
                    lastOperationErrorMessage = error.localizedDescription
                    return
                }
            }
        }

        do {
            try await commandService.deleteUserPinboards()
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return
        }
        setSelectedPinboardID(nil)
        invalidateDashboardItems()
        reconcileLockStateForShareMembership()
        await forceCloudConvergenceAfterPinboardMutation()
    }

    public func togglePin(objectID: NSManagedObjectID) async {
        await performMutation { try await commandService.togglePin(objectID: objectID) }
    }

    public func removeItems(
        _ objectIDs: [NSManagedObjectID], fromPinboardID pinboardID: NSManagedObjectID
    )
        async
    {
        guard !objectIDs.isEmpty else { return }
        await performMutation {
            try await commandService.removeItems(
                objectIDs: objectIDs,
                fromPinboardID: pinboardID
            )
            invalidateDashboardItems()
        }
    }

    public func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data)
        async
    {
        await performMutation {
            try await commandService.updateRichTextItem(
                objectID: objectID,
                newText: newText,
                rtfData: rtfData
            )
        }
    }

    public func updateTextItem(objectID: NSManagedObjectID, newText: String) async {
        let hasContent = !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else {
            lastOperationErrorMessage = "Content cannot be empty."
            return
        }

        await performMutation {
            try await commandService.updateTextItem(objectID: objectID, newText: newText)
        }
    }

    public func updateItemType(objectID: NSManagedObjectID, newType: ItemType) async {
        await performMutation {
            try await commandService.updateItemType(objectID: objectID, newType: newType)
            if newType == .url {
                await refreshPendingLinkPreviews()
            }
        }
    }

    public func updateImageItem(objectID: NSManagedObjectID, imageData: Data) async {
        guard !imageData.isEmpty else {
            lastOperationErrorMessage = "Image data is empty."
            return
        }

        await performMutation {
            try await commandService.updateImageData(objectID: objectID, imageData: imageData)
        }
    }

    public func handleDeepLink(_ url: URL) {
        guard let action = AppDeepLinkHandler().action(for: url) else { return }
        apply(action)
    }

    private func apply(_ action: AppDeepLinkAction) {
        switch action {
        case .selectPinboard(let pinboardID):
            setSelectedPinboardID(pinboardID)
        case .selectItem(let itemID):
            if let pinboardID = pinboardIDForItem(itemID: itemID) {
                setSelectedPinboardID(pinboardID)
            }
        case .search:
            selectedTab = .search
            pendingWidgetAction = .search
        case .paste:
            selectedTab = .dashboard
            pendingWidgetAction = .paste
        case .create:
            selectedTab = .dashboard
            pendingWidgetAction = .create
        case .openDashboard:
            selectedTab = .dashboard
        }
    }

    public func acceptShare(metadata: CKShare.Metadata) async {
        guard let syncCoordinator else {
            lastOperationErrorMessage = "iCloud sync is unavailable in this build."
            return
        }

        do {
            try await syncCoordinator.acceptShare(metadata: metadata)
            reconcileLockStateForShareMembership()
            await refreshPendingLinkPreviews()
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func leaveSharedPinboard(objectID: NSManagedObjectID) async {
        guard let sharingRepository else {
            lastOperationErrorMessage = "Sharing is unavailable in this build."
            return
        }

        do {
            try await sharingRepository.leaveShare(pinboardID: objectID)
            reconcileLockStateForShareMembership()
            if let selectedPinboardID,
                let selectedObjectID = objectIDForPinboardUUID(selectedPinboardID),
                selectedObjectID == objectID
            {
                setSelectedPinboardID(nil)
            }
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func stopSharingPinboard(objectID: NSManagedObjectID) async {
        guard let sharingRepository else {
            lastOperationErrorMessage = "Sharing is unavailable in this build."
            return
        }

        do {
            try await sharingRepository.stopSharing(pinboardID: objectID)
            reconcileLockStateForShareMembership()
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    private func maybeStartSyncIfEnabled() async {
        guard let syncCoordinator else { return }
        guard syncCoordinator.syncEnabled else { return }

        do {
            try await syncCoordinator.startSync()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private func refreshDashboardStateFromShareExtensionIfNeeded() {
        let latestShareExtensionSuccessAt = userDefaults.double(
            forKey: MartenIOSDefaults.shareExtensionLastSuccessAtKey
        )
        let latestKeyboardMutationAt = userDefaults.double(
            forKey: MartenIOSDefaults.keyboardLastMutationAtKey
        )
        let hasShareUpdate = latestShareExtensionSuccessAt > lastSeenShareExtensionSuccessAt
        let hasKeyboardMutation = latestKeyboardMutationAt > lastSeenKeyboardMutationAt
        guard hasShareUpdate || hasKeyboardMutation else { return }

        // Earliest timestamp of detected extension writes — anything >= this needs uploading
        let lastCheckDate: Date = {
            var timestamps: [Double] = []
            if hasShareUpdate   { timestamps.append(lastSeenShareExtensionSuccessAt) }
            if hasKeyboardMutation { timestamps.append(lastSeenKeyboardMutationAt) }
            return Date(timeIntervalSince1970: timestamps.min() ?? 0)
        }()

        lastSeenShareExtensionSuccessAt = latestShareExtensionSuccessAt
        lastSeenKeyboardMutationAt = latestKeyboardMutationAt
        invalidateDashboardItems()

        let viewContext = persistenceController.viewContext
        viewContext.performAndWait {
            viewContext.refreshAllObjects()
            viewContext.processPendingChanges()
        }

        syncCoordinator?.enqueueItemsModifiedSince(lastCheckDate)
    }

    private func invalidateDashboardItems() {
        dashboardRefreshRevision &+= 1
    }

    private func reconcileLockStateForShareMembership() {
        let context = persistenceController.viewContext
        var lockableIDs: Set<UUID> = []
        context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == NO AND shareMetadata == nil")
            request.returnsObjectsAsFaults = false
            let pinboards = (try? context.fetch(request)) ?? []
            lockableIDs = Set(pinboards.map(\.id))
        }
        lockStateStore.reconcile(validPinboardIDs: lockableIDs)
    }

    private func reconcileShareMetadataFromTokens() async {
        do {
            let result = try ShareMetadataReconciler().reconcile(
                persistenceController: persistenceController
            )
            if !result.discoveredSharedZoneIDs.isEmpty {
                try? await syncCoordinator?.syncSharedNow()
            }
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    private func sourceAppInfo() -> SourceAppInfo {
        MartenSourceIdentity.sourceAppInfo()
    }

    private func forceCloudConvergenceAfterPinboardMutation() async {
        guard let syncCoordinator else { return }

        do {
            try await syncCoordinator.triggerSyncNow()
            clearSyncError()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private struct SharedPinboardReference {
        let objectID: NSManagedObjectID
        let isOwner: Bool
    }

    private func sharedPinboardReferencesForBulkDelete() -> [SharedPinboardReference] {
        let context = persistenceController.viewContext
        var references: [SharedPinboardReference] = []

        context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == NO AND shareMetadata != nil")
            request.returnsObjectsAsFaults = false

            let pinboards = (try? context.fetch(request)) ?? []
            references = pinboards.compactMap { pinboard in
                guard let metadata = pinboard.shareMetadata else { return nil }
                return SharedPinboardReference(
                    objectID: pinboard.objectID,
                    isOwner: metadata.isOwner
                )
            }
        }

        return references
    }

    private func performMutation(_ operation: () async throws -> Void) async {
        do { try await operation() }
        catch { lastOperationErrorMessage = error.localizedDescription }
    }

    private func objectIDForPinboardUUID(_ pinboardID: UUID) -> NSManagedObjectID? {
        let context = persistenceController.viewContext
        var objectID: NSManagedObjectID?
        context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", pinboardID as NSUUID)
            objectID = try? context.fetch(request).first?.objectID
        }
        return objectID
    }

    private func pinboardIDForItem(itemID: UUID) -> UUID? {
        let context = persistenceController.viewContext
        var resolvedPinboardID: UUID?
        context.performAndWait {
            let request = ClipItem.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", itemID as NSUUID)
            if let item = try? context.fetch(request).first {
                let pinboards = (item.pinboards ?? [])
                    .filter { !$0.isSystemMarten }
                    .sorted { $0.sortOrder < $1.sortOrder }
                resolvedPinboardID = pinboards.first?.id
            }
        }
        return resolvedPinboardID
    }

    private func isSelectablePinboard(_ pinboardID: UUID) -> Bool {
        let context = persistenceController.viewContext
        var isSelectable = false
        context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "id == %@ AND isSystemMarten == NO",
                pinboardID as NSUUID
            )
            isSelectable = ((try? context.fetch(request).first) != nil)
        }
        return isSelectable
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
            setSelectedPinboardID(survivingID)
        }
    }
}

