import AppKit
import ClipboardCore
import SwiftUI

/// A separate borderless window that displays drag preview outside the main overlay bounds.
///
/// Uses a two-layer approach for instant display:
/// 1. An `NSImageView` (pure AppKit) shows a card snapshot instantly on the first frame.
/// 2. An `NSHostingView` (SwiftUI) renders the full preview on top, covering the snapshot.
class DragPreviewWindow: NSWindow {
    private var hostingView: NSHostingView<DragPreviewWindowContent>?
    private var snapshotImageView: NSImageView?

    private class FlippedContainer: NSView {
        override var isFlipped: Bool { true }
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .popUpMenu + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let size = NSSize(width: 600, height: 600)
        let container = FlippedContainer(frame: NSRect(origin: .zero, size: size))

        // Snapshot layer (behind SwiftUI) — displays instantly via AppKit
        let imageView = NSImageView(frame: .zero)
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        container.addSubview(imageView)
        self.snapshotImageView = imageView

        // SwiftUI layer (on top) — renders the full preview
        let rootView = DragPreviewWindowContent(data: nil)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        self.hostingView = hosting

        self.contentView = container
        self.setFrame(NSRect(origin: .zero, size: size), display: false)
    }

    /// Capture the visible card content as an `NSImage`, cropped to the card area.
    ///
    /// The hosting view is 600x600 with the card centered at (300, 300).
    /// We crop to just the card region so the native drag image shows the actual card.
    func capturePreviewImage(data: DragPreviewData?) -> NSImage? {
        guard let hostingView, isVisible, let data else { return nil }
        let bounds = hostingView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Compute the content rect within the 600x600 window.
        // Cards are centered at (300, 300) via .position(x:y:).
        let stackPadding: CGFloat = data.items.count > 1 ? 12 : 0
        let contentWidth = data.cardSize + stackPadding
        let contentHeight: CGFloat = (data.isCompactLayout ? 70 : data.cardSize) + stackPadding

        let cropRect = NSRect(
            x: 300 - contentWidth / 2,
            y: 300 - contentHeight / 2,
            width: contentWidth,
            height: contentHeight
        )

        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: bounds, to: bitmapRep)

        let fullImage = NSImage(size: bounds.size)
        fullImage.addRepresentation(bitmapRep)

        // Crop to the content area
        let scale = fullImage.representations.first.map {
            CGFloat($0.pixelsWide) / fullImage.size.width
        } ?? 1
        let pixelCrop = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )

        guard let fullCGImage = fullImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else { return nil }

        guard let croppedCG = fullCGImage.cropping(to: pixelCrop) else { return nil }

        return NSImage(
            cgImage: croppedCG,
            size: NSSize(width: cropRect.width, height: cropRect.height)
        )
    }

    func updatePreview(_ data: DragPreviewData?) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = DragPreviewWindowContent(data: data)

        // Show snapshot on the AppKit image view (instant, no SwiftUI render needed)
        if let snapshot = data?.snapshotImage {
            let imgSize = snapshot.size
            let scaled = NSSize(width: imgSize.width * 0.96, height: imgSize.height * 0.96)
            snapshotImageView?.frame = NSRect(
                x: 300 - scaled.width / 2,
                y: 300 - scaled.height / 2,
                width: scaled.width,
                height: scaled.height
            )
            snapshotImageView?.image = snapshot
            snapshotImageView?.alphaValue = CGFloat(data?.opacity ?? 0.9)
        }

        if data != nil {
            if !self.isVisible {
                // Force layout so the new content is rendered before the window appears,
                // preventing a flash of stale content from a previous drag.
                hostingView.layoutSubtreeIfNeeded()
                self.orderFront(nil)
            }
        } else {
            snapshotImageView?.image = nil
            if self.isVisible {
                self.orderOut(nil)
            }
        }
    }
}

private struct DragPreviewWindowContent: View {
    let data: DragPreviewData?

    var body: some View {
        ZStack {
            if let data = data {
                GeometryReader { _ in
                    if data.isCompactLayout {
                        // Compact row layout preview
                        if data.items.count == 1, let item = data.items.first {
                            ItemCompactRowDragPreview(item: item, pinboards: data.pinboards, width: data.cardSize)
                                .frame(width: data.cardSize, height: 70)
                                .position(x: 300, y: 300)
                                .opacity(data.opacity)
                        } else if data.items.count > 1 {
                            MultiItemCompactRowDragPreview(
                                items: data.items,
                                pinboards: data.pinboards,
                                width: data.cardSize
                            )
                            .position(x: 300, y: 300)
                            .opacity(data.opacity)
                        }
                    } else {
                        // Card layout preview
                        if data.items.count == 1, let item = data.items.first {
                            ItemCardDragPreview(item: item, pinboards: data.pinboards, cardSize: data.cardSize)
                                .frame(width: data.cardSize, height: data.cardSize)
                                .position(x: 300, y: 300) // Center of the 600x600 window
                                .opacity(data.opacity)
                        } else if data.items.count > 1 {
                            MultiItemCardDragPreview(
                                items: data.items,
                                pinboards: data.pinboards,
                                cardSize: data.cardSize
                            )
                            .position(x: 300, y: 300)
                            .opacity(data.opacity)
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 600)
        .allowsHitTesting(false)
    }
}

// MARK: - Pinboard Drag Preview Window

/// Data for pinboard tab drag preview
struct PinboardDragPreviewData: Equatable {
    let title: String
    let colorHex: String?
    let iconName: String?
    let size: CGSize
    let opacity: Double
}

/// A separate borderless window that displays pinboard tab drag preview outside the main overlay bounds
class PinboardDragPreviewWindow: NSWindow {
    private var hostingView: NSHostingView<PinboardDragPreviewWindowContent>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .popUpMenu + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = PinboardDragPreviewWindowContent(data: nil)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 300, height: 100))
        self.contentView = hosting
        self.hostingView = hosting

        self.setFrame(NSRect(origin: .zero, size: NSSize(width: 300, height: 100)), display: false)
    }

    func updatePreview(_ data: PinboardDragPreviewData?) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = PinboardDragPreviewWindowContent(data: data)

        if data != nil {
            if !self.isVisible {
                self.orderFront(nil)
            }
        } else {
            if self.isVisible {
                self.orderOut(nil)
            }
        }
    }
}

private struct PinboardDragPreviewWindowContent: View {
    let data: PinboardDragPreviewData?

    var body: some View {
        ZStack {
            if let data = data {
                GeometryReader { _ in
                    PinboardTabPreviewView(
                        title: data.title,
                        colorHex: data.colorHex,
                        iconName: data.iconName
                    )
                        .frame(width: data.size.width, height: data.size.height)
                        .position(x: 150, y: 50) // Center of the 300x100 window
                        .opacity(data.opacity)
                }
            }
        }
        .frame(width: 300, height: 100)
        .allowsHitTesting(false)
    }
}

/// Standalone pinboard tab preview for the drag window
private struct PinboardTabPreviewView: View {
    let title: String
    let colorHex: String?
    let iconName: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            if let colorHex {
                PinboardIndicator(colorHex: colorHex, sign: iconName, size: 16)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 20)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            Group {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassNavigationStyle()
                } else {
                    (colorScheme == .dark ? Color.white : Color.black).opacity(0.3)
                }
            }
        )
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
    }
}

// MARK: - Compact Row Drag Preview

/// Compact row drag preview for vertical layout.
/// Uses the same visual styling as `ItemCompactRow` (solid background, shadow, app color sidebar)
/// but without heavy modifiers (.popover, .contextMenu) that interfere in a drag preview window.
struct ItemCompactRowDragPreview: View {
    let item: ClipItem
    let pinboards: [Pinboard]
    let width: CGFloat

    private let cardCornerRadius: CGFloat = 12
    private let sideBarWidth: CGFloat = 38

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            rightInfoColumn
        }
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(width: width, height: 70, alignment: .leading)
        .background(rowBackground)
        .clipShape(cardShape)
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1),
            radius: 3,
            x: 0,
            y: 1
        )
        .allowsHitTesting(false)
        .opacity(0.9)
        .scaleEffect(0.96)
        .accessibilityHidden(true)
    }

    private var leadingVisual: some View {
        ZStack {
            if let pinboard = primaryAssignedPinboard {
                if let signKind = PinboardSignResolver.resolve(pinboard.iconName) {
                    switch signKind {
                    case .symbol(let symbol):
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(sideBarContentColor)
                            .shadow(color: sideBarContentShadowColor, radius: 1, y: 0.4)
                    case .text(let token):
                        Text(token)
                            .font(.system(size: 15))
                            .foregroundStyle(sideBarContentColor)
                            .shadow(color: sideBarContentShadowColor, radius: 1, y: 0.4)
                    }
                }
            } else {
                AppIconView(bundleID: item.sourceAppBundleID, size: 19)
            }
        }
        .frame(width: sideBarWidth, alignment: .center)
        .frame(maxHeight: .infinity)
    }

    private var rightInfoColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                }

                Image(systemName: typeIcon)
                    .font(.system(size: 8, weight: .semibold))
                Text(typeCompactLabel)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06)
                    )
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // Background matches ItemCompactRow / ItemCard: solid fill visible on a transparent window.
    private var rowBackground: some View {
        ZStack(alignment: .leading) {
            cardShape
                .fill(colorScheme == .dark
                    ? Color(.sRGB, white: 0.04, opacity: 0.72)
                    : Color(.sRGB, white: 0.96, opacity: 0.9))
            Rectangle()
                .fill(sideBarColor)
                .frame(width: sideBarWidth)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    private var sideBarColor: Color {
        if let pinboard = primaryAssignedPinboard {
            return Color(hex: pinboard.colorHex, fallback: .gray)
        }
        if let bundleID = item.sourceAppBundleID,
           let appColor = AppIconCache.shared.cachedColor(bundleID: bundleID) {
            return Color(nsColor: appColor).opacity(0.9)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.24)
    }

    private var sideBarContentColor: Color {
        sideBarIsDark ? .white.opacity(0.95) : .black.opacity(0.78)
    }

    private var sideBarContentShadowColor: Color {
        sideBarIsDark ? .black.opacity(0.26) : .white.opacity(0.12)
    }

    private var sideBarIsDark: Bool {
        let color = sideBarNSColor.usingColorSpace(.sRGB) ?? sideBarNSColor
        let luminance = (0.2126 * color.redComponent)
            + (0.7152 * color.greenComponent)
            + (0.0722 * color.blueComponent)
        return luminance < 0.58
    }

    private var sideBarNSColor: NSColor {
        if let pinboard = primaryAssignedPinboard {
            return NSColor(hex: pinboard.colorHex)
        }
        if let bundleID = item.sourceAppBundleID,
           let appColor = AppIconCache.shared.cachedColor(bundleID: bundleID) {
            return appColor
        }
        return colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.24)
    }

    private var primaryAssignedPinboard: Pinboard? {
        let assigned = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        return assigned.sorted(by: { $0.sortOrder < $1.sortOrder }).first
    }

    private var titleText: String {
        if let customTitle = item.customTitle, !customTitle.isEmpty {
            return customTitle
        }
        let text = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
        return typeLabel
    }

    private var subtitle: String? {
        if let appName = item.sourceAppName, !appName.isEmpty {
            return appName
        }
        if let bundleID = item.sourceAppBundleID, !bundleID.isEmpty {
            return bundleID
        }
        return nil
    }

    private var typeLabel: String {
        switch item.itemTypeValue {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "URL"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }

    private var typeCompactLabel: String {
        switch item.itemTypeValue {
        case .richText: return "Rich"
        case .mixed: return "Mixed"
        default: return typeLabel
        }
    }

    private var typeIcon: String {
        switch item.itemTypeValue {
        case .text: return "textformat"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .code: return "chevron.left.slash.chevron.right"
        case .color: return "paintpalette"
        case .mixed: return "square.stack"
        }
    }
}

/// Multi-item compact row drag preview for vertical layout
struct MultiItemCompactRowDragPreview: View {
    let items: [ClipItem]
    let pinboards: [Pinboard]
    let width: CGFloat

    private let stackOffset: CGFloat = 3
    private let maxVisibleRows = 3
    private static let stackRotations: [Double] = [0, 1.5, -2]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.prefix(maxVisibleRows).enumerated()), id: \.offset) { index, item in
                ItemCompactRowDragPreview(item: item, pinboards: pinboards, width: width)
                    .frame(width: width, height: 70)
                    .rotationEffect(.degrees(Self.stackRotations[min(index, Self.stackRotations.count - 1)]))
                    .offset(
                        x: CGFloat(index) * stackOffset,
                        y: CGFloat(index) * stackOffset
                    )
                    .opacity(0.9 - (Double(index) * 0.1))
            }

            if items.count > maxVisibleRows {
                Text("\(items.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                            .shadow(radius: 2)
                    )
                    .offset(x: width - 30, y: -8)
            }
        }
        .scaleEffect(0.96)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
