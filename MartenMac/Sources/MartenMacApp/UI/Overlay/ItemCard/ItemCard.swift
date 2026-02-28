import AppKit
import MartenCore
import SwiftUI
import CoreData

struct ItemCard: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let selectedPinboardID: UUID?
    var itemPinboardSignature: Int = 0
    let isSelected: Bool
    let isEditing: Bool
    let badgeIndex: Int?
    let isDropTarget: Bool
    let showPinIndicator: Bool
    let allowPinning: Bool
    let readOnly: Bool
    let isDragEnabled: Bool
    let cardSize: CGFloat
    let onPaste: (ClipItem) -> Void
    let onPastePlainText: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onConvertType: (ClipItem, ItemType) -> Void
    let onMoveToPinboard: (ClipItem, Pinboard) -> Void
    let onCreatePinboard: (ClipItem) -> Void
    let onEdit: (ClipItem) -> Void
    let onRename: (ClipItem) -> Void
    let onCommitRename: (ClipItem, String) -> Void
    let onTap: (ClipItem) -> Void
    let onDoubleTap: (ClipItem) -> Void

    @State private var lastTapTime: Date?
    @State var editTitle: String = ""
    @State var cachedProps: CachedItemProperties?
    @StateObject var appColorLoader = AppIconColorLoader()
    @State var thumbnailImage: NSImage?
    @State var fileIconImage: NSImage?
    @State var urlBannerImage: NSImage?
    @State var lastLoadedThumbnailPath: String?
    @State var lastLoadedURLBannerPath: String?
    @State var lastFetchedURLBannerURLString: String?
    @State var styledPreviewText: AttributedString?
    @State var originalImageResolution: String?
    @State var imageResolutionRequestID: UUID = UUID()
    @State var lastKnownModifiedAt: Date = Date()
    @FocusState var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if item.isDeleted || item.managedObjectContext == nil {
                EmptyView()
            } else {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        headerView
                        VStack(alignment: .leading, spacing: 0) {
                            if isEdgeToEdgeContent {
                                contentPreviewView
                            } else {
                                contentPreviewView
                                    .padding(.horizontal, cardPadding)
                                    .padding(.top, isCompactSize ? 8 : 10)
                            }
                            Spacer(minLength: 0)
                            footerView
                                .padding(.horizontal, cardPadding)
                                .padding(.bottom, cardPadding)
                                .padding(.top, isCompactSize ? 6 : 8)
                        }
                    }
                    .frame(width: cardSize, height: cardSize, alignment: .topLeading)
                    .background(cardBackground)
                    .clipShape(cardShape)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.12),
                        radius: isSelected ? 6 : 4,
                        x: 0,
                        y: isSelected ? 3 : 2
                    )
                    .overlay(selectionBorder)
                    .contentShape(cardShape)

                }
                .onTapGesture {
                    let now = Date()
                    if let lastTime = lastTapTime, now.timeIntervalSince(lastTime) < 0.3 {
                        onDoubleTap(item)
                        lastTapTime = nil
                    } else {
                        onTap(item)
                        lastTapTime = now
                    }
                }
                .onAppear {
                    cachedProps = CachedItemProperties(item: item)
                    appColorLoader.load(bundleID: item.sourceAppBundleID, appName: item.sourceAppName)
                    lastKnownModifiedAt = item.modifiedAt
                    refreshPreviewAssets()
                    refreshStyledPreviewText()
                }
                .onChange(of: contentSignature) { oldValue, newValue in
                    if item.isDeleted || item.managedObjectContext == nil { return }

                    if let currentPinboardID = selectedPinboardID {
                        let isInCurrent = item.pinboards?.contains { $0.id == currentPinboardID } ?? false
                        if !isInCurrent { return }
                    }

                    cachedProps = CachedItemProperties(item: item)
                    lastKnownModifiedAt = newValue.modifiedAt

                    if oldValue.sourceAppBundleID != newValue.sourceAppBundleID
                        || oldValue.sourceAppName != newValue.sourceAppName {
                        appColorLoader.load(
                            bundleID: newValue.sourceAppBundleID,
                            appName: newValue.sourceAppName
                        )
                    }

                    if oldValue.primaryText != newValue.primaryText {
                        resetURLBannerState()
                    }

                    if oldValue.thumbnailPath != newValue.thumbnailPath {
                        refreshThumbnailImage()
                        refreshImageResolution()
                    }

                    if oldValue.representationAssetSignature != newValue.representationAssetSignature {
                        refreshThumbnailImage()
                        refreshImageResolution()
                    }

                    if oldValue.linkPreviewImagePath != newValue.linkPreviewImagePath
                        || oldValue.primaryText != newValue.primaryText
                    {
                        refreshURLBannerImage()
                    }

                    if oldValue.modifiedAt != newValue.modifiedAt || oldValue.itemType != newValue.itemType {
                        refreshPreviewAssets()
                    }

                    if oldValue.primaryText != newValue.primaryText
                        || oldValue.customTitle != newValue.customTitle
                        || oldValue.modifiedAt != newValue.modifiedAt
                        || oldValue.itemType != newValue.itemType
                    {
                        refreshStyledPreviewText()
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSManagedObjectContext.didMergeChangesObjectIDsNotification
                    )
                ) { notification in
                    guard let context = item.managedObjectContext else { return }
                    let userInfo = notification.userInfo
                    let updatedIDs = (userInfo?[NSUpdatedObjectIDsKey] as? Set<NSManagedObjectID>) ?? []
                    let insertedIDs = (userInfo?[NSInsertedObjectIDsKey] as? Set<NSManagedObjectID>) ?? []
                    let changed = updatedIDs.union(insertedIDs)
                    guard !changed.isEmpty else { return }

                    context.perform {
                        let representationIDs = (item.representations ?? []).map(\.objectID)
                        let hasRepresentationChange = representationIDs.contains { changed.contains($0) }
                        let hasItemChange = changed.contains(item.objectID)
                        guard hasItemChange || hasRepresentationChange else { return }

                        Task { @MainActor in
                            cachedProps = CachedItemProperties(item: item)
                            lastKnownModifiedAt = item.modifiedAt
                            refreshPreviewAssets()
                            refreshStyledPreviewText()
                        }
                    }
                }
                .accessibilityElement(children: isEditing ? .contain : .ignore)
                .accessibilityIdentifier("overlay.itemCard.\(item.id.uuidString)")
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityValue(accessibilityValueText)
                .accessibilityHint(accessibilityHintText)
                .accessibilityAddTraits(.isButton)
                .contextMenu {
                    contextMenuContent
                }
            }
        }
    }

    var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    var normalizedColorHex: String? {
        guard item.itemTypeValue == .color, let text = item.primaryText else { return nil }
        return MartenHexColor.normalizedHex(from: text)
    }

    var colorItemBackground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return Color(hex: hex, fallback: .gray)
    }

    var colorItemForeground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return MartenHexColor.foregroundColor(forNormalizedHex: hex)
    }

    var assignedPinboardIDs: Set<UUID> {
        let assigned = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        return Set(assigned.map(\.id))
    }

    private var contentSignature: ContentSignature {
        ContentSignature(item: item)
    }
}

private struct ContentSignature: Equatable {
    let primaryText: String?
    let thumbnailPath: String?
    let representationAssetSignature: String
    let customTitle: String?
    let linkPreviewImagePath: String?
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let modifiedAt: Date
    let itemType: ItemType
    let pinboardAssignmentSignature: Int

    init(item: ClipItem) {
        primaryText = item.primaryText
        thumbnailPath = item.thumbnailPath
        representationAssetSignature = (item.representations ?? [])
            .map { representation in
                let assetRef = representation.assetRef?.uuidString ?? "none"
                let fileExtension = representation.fileExtension?.lowercased() ?? "none"
                return "\(assetRef).\(fileExtension)"
            }
            .sorted()
            .joined(separator: ",")
        customTitle = item.customTitle
        linkPreviewImagePath = item.linkPreview?.imagePath
        sourceAppBundleID = item.sourceAppBundleID
        sourceAppName = item.sourceAppName
        modifiedAt = item.modifiedAt
        itemType = item.itemTypeValue

        pinboardAssignmentSignature = pinboardSignature(for: item)
    }
}
