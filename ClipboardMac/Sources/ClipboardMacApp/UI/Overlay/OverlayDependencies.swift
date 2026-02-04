import ClipboardCore
import ClipboardMacServices
import CoreData

public typealias AppleIntelligenceTextServicing = AppleIntelligenceTextTransforming

@MainActor
public protocol ItemOperating: AnyObject {
    func copyItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        orderedItems: [ClipItem],
        eventBroadcaster: any ClipboardEventBroadcaster
    )
    func deleteItem(
        _ item: ClipItem,
        selectedItemIDs: Set<NSManagedObjectID>,
        onClearSelection: () -> Void
    )
    func commitItemRename(itemID: NSManagedObjectID, newTitle: String)
    func updateImageData(itemID: NSManagedObjectID, imageData: Data)
    func updateFileName(itemID: NSManagedObjectID, newFileName: String)
    func togglePin(_ item: ClipItem, allowPinning: Bool)
}

extension ItemOperationsHandler: ItemOperating {}

@MainActor
public protocol PinboardManaging: AnyObject {
    func deletePinboard(_ pinboard: Pinboard, selectedPinboardID: UUID?) -> UUID?
    func renamePinboard(
        objectID: NSManagedObjectID,
        name: String,
        colorHex: String,
        iconName: String?
    ) -> Bool
    func createPinboard(
        name: String,
        colorHex: String,
        iconName: String?,
        pendingItem: ClipItem?
    ) -> Bool
    func changePinboardColor(_ pinboard: Pinboard, hex: String)
    func changePinboardIcon(_ pinboard: Pinboard, iconName: String?)
    func toggleItem(_ item: ClipItem, in pinboard: Pinboard)
    func moveItemToPinboard(_ pinboard: Pinboard, itemURIString: String)
    func handleDropToPinboard(item: ClipItem, pinboardID: NSManagedObjectID) -> Bool
    func handleDropToAll(item: ClipItem, selectedPinboard: Pinboard?) -> Bool
    func optimisticReorderPinboards(
        dragged: Pinboard,
        target: Pinboard,
        insertBefore: Bool,
        visiblePinboards: [Pinboard]
    )
    func saveChanges()
}

extension PinboardManager: PinboardManaging {}

public struct OverlayDependencies {
    public let clipItemStore: any ClipItemStoring
    public let itemOperations: any ItemOperating
    public let pinboards: any PinboardManaging
    public let previewCoordinator: OverlayPreviewCoordinator
    public let appleIntelligence: any AppleIntelligenceTextServicing
    public let soundPlayer: SoundEffectPlayer

    public init(
        clipItemStore: any ClipItemStoring,
        itemOperations: any ItemOperating,
        pinboards: any PinboardManaging,
        previewCoordinator: OverlayPreviewCoordinator,
        appleIntelligence: any AppleIntelligenceTextServicing,
        soundPlayer: SoundEffectPlayer
    ) {
        self.clipItemStore = clipItemStore
        self.itemOperations = itemOperations
        self.pinboards = pinboards
        self.previewCoordinator = previewCoordinator
        self.appleIntelligence = appleIntelligence
        self.soundPlayer = soundPlayer
    }
}

