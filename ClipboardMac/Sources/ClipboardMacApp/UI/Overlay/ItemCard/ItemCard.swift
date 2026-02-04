import AppKit
import ClipboardCore
import SwiftUI

struct ItemCard: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
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
            cachedProps = CachedItemProperties(item: item)
            appColorLoader.load(bundleID: item.sourceAppBundleID)
            refreshPreviewAssets()
            refreshStyledPreviewText()
        }
        .onChange(of: item.objectID) { _, _ in
            cachedProps = CachedItemProperties(item: item)
            appColorLoader.load(bundleID: item.sourceAppBundleID)
            refreshPreviewAssets()
            refreshStyledPreviewText()
        }
        .onChange(of: item.linkPreview?.imagePath) { _, _ in
            refreshURLBannerImage()
        }
        .onChange(of: item.thumbnailPath) { _, _ in
            refreshThumbnailImage()
        }
        .onChange(of: item.modifiedAt) { _, _ in
            refreshPreviewAssets()
            refreshStyledPreviewText()
        }
        .onChange(of: item.primaryText) { _, _ in
            resetURLBannerState()
            refreshURLBannerImage()
        }
        .onChange(of: item.sourceAppBundleID) { newValue, _ in
            appColorLoader.load(bundleID: newValue)
        }
        .onReceive(item.objectWillChange) { _ in
            DispatchQueue.main.async {
                cachedProps = CachedItemProperties(item: item)
                refreshURLBannerImage()
                refreshStyledPreviewText()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
}
