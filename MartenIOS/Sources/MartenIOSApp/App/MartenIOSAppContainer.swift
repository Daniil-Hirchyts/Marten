import CloudKit
import CoreData
import Foundation
import MartenCore
import SwiftUI

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
        self.lockStateStore = PinboardLockStateStore(userDefaults: userDefaults)

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

        self.syncCoordinator = Self.makeSyncCoordinator(
            persistenceController: persistenceController,
            userDefaults: userDefaults,
            syncConfigurationProvider: syncConfigurationProvider
        )
        self.sharingRepository =
            sharingRepository
            ?? Self.makeSharingRepository(
                persistenceController: persistenceController,
                syncConfigurationProvider: syncConfigurationProvider
            )
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        ensureSystemPinboardExists()
        await maybeStartSyncIfEnabled()
        ensureSystemPinboardExists()
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
            ensureSystemPinboardExists()
            await refreshPendingLinkPreviews()
            refreshDashboardStateFromShareExtensionIfNeeded()
        case .background:
            if let syncCoordinator, syncCoordinator.syncEnabled {
                syncCoordinator.stopSync()
            }
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

    public func refreshPendingLinkPreviews() async {
        await linkPreviewCoordinator.fetchPending(limit: 25)
    }

    public func createTextItem(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await commandService.createTextItem(
                text: trimmed,
                sourceApp: sourceAppInfo(),
                isUserCreated: true
            )
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func createRichTextItem(plainText: String, rtfData: Data) async {
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
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
                itemType: .richText
            )

            try await commandService.createItem(
                payload: payload,
                sourceApp: sourceAppInfo(),
                isUserCreated: true
            )
        } catch {
            lastOperationErrorMessage = error.localizedDescription
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

    public func createScannedPages(_ pageJPEGData: [Data]) async {
        guard !pageJPEGData.isEmpty else { return }

        do {
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
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func createPinboard(name: String, colorHex: String, iconName: String?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastOperationErrorMessage = "Pinboard name cannot be empty."
            return
        }

        do {
            try await commandService.createPinboard(
                name: trimmed,
                colorHex: colorHex,
                iconName: iconName
            )
        } catch {
            lastOperationErrorMessage = error.localizedDescription
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

        do {
            try await commandService.updatePinboard(
                objectID: objectID,
                name: trimmed,
                colorHex: colorHex,
                iconName: iconName
            )
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func deletePinboard(_ pinboard: Pinboard) async {
        guard !pinboard.isSystemMarten else {
            lastOperationErrorMessage = "Clipboard History pinboard cannot be deleted."
            return
        }

        do {
            try await commandService.deletePinboard(objectID: pinboard.objectID)
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func moveItems(
        _ objectIDs: [NSManagedObjectID], toPinboardID pinboardID: NSManagedObjectID
    )
        async
    {
        guard !objectIDs.isEmpty else { return }

        do {
            try await commandService.moveItems(
                objectIDs: objectIDs,
                toPinboardID: pinboardID
            )
            invalidateDashboardItems()
        } catch {
            lastOperationErrorMessage = error.localizedDescription
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

        do {
            try await commandService.deleteItems(objectIDs: objectIDs)
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func togglePin(objectID: NSManagedObjectID) async {
        do {
            try await commandService.togglePin(objectID: objectID)
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func removeItems(
        _ objectIDs: [NSManagedObjectID], fromPinboardID pinboardID: NSManagedObjectID
    )
        async
    {
        guard !objectIDs.isEmpty else { return }

        do {
            try await commandService.removeItems(
                objectIDs: objectIDs,
                fromPinboardID: pinboardID
            )
            invalidateDashboardItems()
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data)
        async
    {
        do {
            try await commandService.updateRichTextItem(
                objectID: objectID,
                newText: newText,
                rtfData: rtfData
            )
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }

    public func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "marten" else { return }

        var components: [String] = []
        if let host = url.host, !host.isEmpty {
            components.append(host)
        }
        components.append(contentsOf: url.pathComponents.filter { $0 != "/" })
        guard let route = components.first?.lowercased() else { return }

        switch route {
        case "pinboard":
            guard components.count >= 2, let pinboardID = UUID(uuidString: components[1]) else {
                return
            }
            setSelectedPinboardID(pinboardID)
        case "item":
            guard components.count >= 2, let itemID = UUID(uuidString: components[1]) else {
                return
            }
            if let pinboardID = pinboardIDForItem(itemID: itemID) {
                setSelectedPinboardID(pinboardID)
            }
        case "search":
            selectedTab = .search
            pendingWidgetAction = .search
        case "paste":
            selectedTab = .dashboard
            pendingWidgetAction = .paste
        case "create":
            selectedTab = .dashboard
            pendingWidgetAction = .create
        case "open":
            selectedTab = .dashboard
        default:
            break
        }
    }

    public func acceptShare(metadata: CKShare.Metadata) async {
        guard let syncCoordinator else {
            lastOperationErrorMessage = "iCloud sync is unavailable in this build."
            return
        }

        do {
            try await syncCoordinator.acceptShare(metadata: metadata)
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

        lastSeenShareExtensionSuccessAt = latestShareExtensionSuccessAt
        lastSeenKeyboardMutationAt = latestKeyboardMutationAt
        invalidateDashboardItems()

        let viewContext = persistenceController.viewContext
        viewContext.performAndWait {
            viewContext.refreshAllObjects()
            viewContext.processPendingChanges()
        }
    }

    private func invalidateDashboardItems() {
        dashboardRefreshRevision &+= 1
    }

    private func sourceAppInfo() -> SourceAppInfo {
        MartenSourceIdentity.sourceAppInfo()
    }

    private static func makeSyncCoordinator(
        persistenceController: PersistenceController,
        userDefaults: UserDefaults,
        syncConfigurationProvider: any MartenIOSSyncConfigurationProviding
    ) -> SyncCoordinator? {
        let cloudKitConfiguration = CloudKitConfiguration.default

        guard
            syncConfigurationProvider.canUseCloudKit(
                containerIdentifier: cloudKitConfiguration.containerIdentifier
            )
        else {
            return nil
        }

        let syncCoordinator = SyncCoordinator.create(
            cloudKitConfiguration: cloudKitConfiguration,
            persistenceController: persistenceController,
            userDefaults: userDefaults,
            syncEnabledProvider: {
                UserDefaults.standard.bool(forKey: MartenIOSDefaults.syncEnabledKey)
            }
        )

        syncCoordinator.syncEnabled = syncConfigurationProvider.isSyncEnabled(userDefaults)

        return syncCoordinator
    }

    private static func makeSharingRepository(
        persistenceController: PersistenceController,
        syncConfigurationProvider: any MartenIOSSyncConfigurationProviding
    ) -> (any PinboardSharingRepositoryProtocol)? {
        guard SharedPinboardsFeatureFlag.isEnabled else {
            return nil
        }

        let cloudKitConfiguration = CloudKitConfiguration.default
        guard
            syncConfigurationProvider.canUseCloudKit(
                containerIdentifier: cloudKitConfiguration.containerIdentifier)
        else {
            return nil
        }

        let zoneID = CKRecordZone.ID(
            zoneName: cloudKitConfiguration.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let cloudKitManager = CloudKitManager(configuration: cloudKitConfiguration)
        let recordMapper = CloudRecordMapper(zoneID: zoneID)
        let shareCoordinator = ShareCoordinator(
            cloudKitManager: cloudKitManager,
            persistenceController: persistenceController,
            recordMapper: recordMapper
        )
        return PinboardSharingRepository(
            shareCoordinator: shareCoordinator,
            persistenceController: persistenceController
        )
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
        var survivingSystemPinboardID: UUID?
        var removedSystemPinboardIDs = Set<UUID>()

        do {
            try context.performAndWaitThrowing {
                let request = Pinboard.fetchRequest()
                request.predicate = NSPredicate(format: "isSystemMarten == YES")

                let systemPinboards = try context.fetch(request)

                if systemPinboards.isEmpty {
                    guard
                        let pinboard = NSEntityDescription.insertNewObject(
                            forEntityName: "Pinboard",
                            into: context
                        ) as? Pinboard
                    else {
                        return
                    }

                    pinboard.id = UUID()
                    pinboard.name = "Marten"
                    pinboard.colorHex = "#808080"
                    pinboard.sortOrder = 0
                    pinboard.isSystemMarten = true
                    pinboard.createdAt = Date()
                    survivingSystemPinboardID = pinboard.id

                    try context.save()
                    return
                }

                let sortedPinboards = systemPinboards.sorted { lhs, rhs in
                    let lhsItemCount = lhs.items?.count ?? 0
                    let rhsItemCount = rhs.items?.count ?? 0
                    if lhsItemCount != rhsItemCount {
                        return lhsItemCount > rhsItemCount
                    }
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                guard let canonical = sortedPinboards.first else { return }
                survivingSystemPinboardID = canonical.id

                canonical.name = "Marten"
                canonical.colorHex = "#808080"
                canonical.sortOrder = 0
                canonical.isSystemMarten = true

                for duplicate in sortedPinboards.dropFirst() {
                    removedSystemPinboardIDs.insert(duplicate.id)

                    if let items = duplicate.items {
                        for item in items where !(canonical.items?.contains(item) ?? false) {
                            canonical.addToItems(item)
                        }
                    }

                    context.delete(duplicate)
                }

                if context.hasChanges {
                    try context.save()
                }
            }
        } catch {
            lastOperationErrorMessage = error.localizedDescription
            return
        }

        if let selectedPinboardID,
            removedSystemPinboardIDs.contains(selectedPinboardID)
        {
            setSelectedPinboardID(survivingSystemPinboardID)
        }
    }
}
