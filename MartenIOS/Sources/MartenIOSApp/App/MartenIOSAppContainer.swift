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

    public var selectedTab: MartenIOSTab = .dashboard
    public var selectedPinboardID: UUID?
    public var shouldShowIntegrationsOnboarding: Bool {
        didSet {
            userDefaults.set(
                shouldShowIntegrationsOnboarding,
                forKey: MartenIOSDefaults.showIntegrationsOnboardingKey
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
            syncConfigurationProvider: MartenIOSSyncConfigurationProvider()
        )
    }

    init(
        persistenceController: PersistenceController = .shared,
        clipItemStore: ClipItemStore? = nil,
        userDefaults: UserDefaults = .standard,
        clipboardReader: any ClipboardReading = SystemClipboardReader(),
        clipboardPayloadBuilder: ClipboardPayloadBuilder = ClipboardPayloadBuilder(),
        linkPreviewFetcher: any LinkPreviewFetching = LinkPreviewFetcher(),
        syncConfigurationProvider: any MartenIOSSyncConfigurationProviding = MartenIOSSyncConfigurationProvider(),
        sharingRepository: (any PinboardSharingRepositoryProtocol)? = nil
    ) {
        self.persistenceController = persistenceController
        self.userDefaults = userDefaults
        self.clipboardReader = clipboardReader
        self.clipboardPayloadBuilder = clipboardPayloadBuilder
        self.syncConfigurationProvider = syncConfigurationProvider

        MartenIOSDefaults.registerDefaults(userDefaults)

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

        self.syncCoordinator = Self.makeSyncCoordinator(
            persistenceController: persistenceController,
            userDefaults: userDefaults,
            syncConfigurationProvider: syncConfigurationProvider
        )
        self.sharingRepository = sharingRepository ?? Self.makeSharingRepository(
            persistenceController: persistenceController,
            syncConfigurationProvider: syncConfigurationProvider
        )
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        ensureSystemPinboardExists()
        await maybeStartSyncIfEnabled()
        await refreshPendingLinkPreviews()
    }

    public func setSelectedPinboardID(_ pinboardID: UUID?) {
        selectedPinboardID = pinboardID
        if let pinboardID {
            userDefaults.set(pinboardID.uuidString, forKey: MartenIOSDefaults.selectedPinboardIDKey)
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
            await maybeStartSyncIfEnabled()
            await refreshPendingLinkPreviews()
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

    public func moveItems(_ objectIDs: [NSManagedObjectID], toPinboardID pinboardID: NSManagedObjectID)
        async
    {
        guard !objectIDs.isEmpty else { return }

        do {
            try await commandService.moveItems(
                objectIDs: objectIDs,
                toPinboardID: pinboardID
            )
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

    public func removeItems(_ objectIDs: [NSManagedObjectID], fromPinboardID pinboardID: NSManagedObjectID)
        async
    {
        guard !objectIDs.isEmpty else { return }

        do {
            try await commandService.removeItems(
                objectIDs: objectIDs,
                fromPinboardID: pinboardID
            )
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

    private func sourceAppInfo() -> SourceAppInfo {
        let bundle = Bundle.main
        let name = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        )

        return SourceAppInfo(
            bundleID: bundle.bundleIdentifier,
            name: name
        )
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
        guard syncConfigurationProvider.canUseCloudKit(containerIdentifier: cloudKitConfiguration.containerIdentifier) else {
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
                    .sorted { lhs, rhs in
                        if lhs.isSystemMarten != rhs.isSystemMarten {
                            return !lhs.isSystemMarten
                        }
                        return lhs.sortOrder < rhs.sortOrder
                    }
                resolvedPinboardID = pinboards.first?.id
            }
        }
        return resolvedPinboardID
    }

    private func ensureSystemPinboardExists() {
        let context = persistenceController.newBackgroundContext()

        do {
            try context.performAndWaitThrowing {
                let request = Pinboard.fetchRequest()
                request.predicate = NSPredicate(format: "isSystemMarten == YES")
                request.fetchLimit = 1

                if try context.fetch(request).isEmpty {
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

                    try context.save()
                }
            }
        } catch {
            lastOperationErrorMessage = error.localizedDescription
        }
    }
}
