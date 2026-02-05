import AppKit
import ClipboardCore
import SwiftUI
import CoreData

struct ItemCard: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let selectedPinboardID: UUID?
    let isSelected: Bool
    let isEditing: Bool
    let badgeIndex: Int?
    let isDropTarget: Bool
    let showPinIndicator: Bool
    let allowPinning: Bool
    let isDragEnabled: Bool
    let cardSize: CGFloat
    let onPaste: () -> Void
    let onPastePlainText: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (Pinboard) -> Void
    let onCreatePinboard: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void
    let onCommitRename: (String) -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void

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
    @FocusState var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                headerView
                VStack(alignment: .leading, spacing: isCompactSize ? 8 : 10) {
                    contentPreviewView
                    Spacer(minLength: 0)
                    footerView
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, cardPadding)
                .padding(.top, isCompactSize ? 8 : 10)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .onTapGesture {
            let now = Date()
            if let lastTime = lastTapTime, now.timeIntervalSince(lastTime) < 0.3 {
                onDoubleTap()
                lastTapTime = nil
            } else {
                onTap()
                lastTapTime = now
            }
        }
        .onAppear {
            cachedProps = OverlayPerformanceSignposts.measure("CachedItemProperties") {
                CachedItemProperties(item: item)
            }
            appColorLoader.load(bundleID: item.sourceAppBundleID)
            refreshPreviewAssets()
            refreshStyledPreviewText()
        }
        .onChange(of: contentSignature) { oldValue, newValue in
            if item.isDeleted || item.managedObjectContext == nil { return }

            if let currentPinboardID = selectedPinboardID {
                let isInCurrent = item.pinboards?.contains { $0.id == currentPinboardID } ?? false
                if !isInCurrent { return }
            }

            cachedProps = OverlayPerformanceSignposts.measure("CachedItemProperties") {
                CachedItemProperties(item: item)
            }

            if oldValue.sourceAppBundleID != newValue.sourceAppBundleID {
                appColorLoader.load(bundleID: newValue.sourceAppBundleID)
            }

            if oldValue.primaryText != newValue.primaryText {
                resetURLBannerState()
            }

            if oldValue.thumbnailPath != newValue.thumbnailPath {
                refreshThumbnailImage()
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

    var cached: CachedItemProperties {
        cachedProps ?? CachedItemProperties(item: item)
    }

    var normalizedColorHex: String? {
        guard item.itemTypeValue == .color, let text = item.primaryText else { return nil }
        return ClipboardHexColor.normalizedHex(from: text)
    }

    var colorItemBackground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return Color(hex: hex, fallback: .gray)
    }

    var colorItemForeground: Color? {
        guard let hex = normalizedColorHex else { return nil }
        return ClipboardHexColor.foregroundColor(forNormalizedHex: hex)
    }

    var assignedPinboardIDs: Set<UUID> {
        let assigned = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        return Set(assigned.map(\.id))
    }

    private var contentSignature: ContentSignature {
        ContentSignature(item: item)
    }
}

private struct ContentSignature: Equatable {
    let primaryText: String?
    let thumbnailPath: String?
    let customTitle: String?
    let linkPreviewImagePath: String?
    let sourceAppBundleID: String?
    let modifiedAt: Date
    let itemType: ItemType

    init(item: ClipItem) {
        primaryText = item.primaryText
        thumbnailPath = item.thumbnailPath
        customTitle = item.customTitle
        linkPreviewImagePath = item.linkPreview?.imagePath
        sourceAppBundleID = item.sourceAppBundleID
        modifiedAt = item.modifiedAt
        itemType = item.itemTypeValue
    }
}
