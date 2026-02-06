import AppKit
import ClipboardCore
import SwiftUI

/// A separate borderless window that displays drag preview outside the main overlay bounds
class DragPreviewWindow: NSWindow {
    private var hostingView: NSHostingView<DragPreviewWindowContent>?

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

        let rootView = DragPreviewWindowContent(data: nil)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 600))
        self.contentView = hosting
        self.hostingView = hosting

        self.setFrame(NSRect(origin: .zero, size: NSSize(width: 600, height: 600)), display: false)
    }

    func updatePreview(_ data: DragPreviewData?) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = DragPreviewWindowContent(data: data)

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

/// Compact row drag preview for vertical layout
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
                    case .text(let token):
                        Text(token)
                            .font(.system(size: 15))
                            .foregroundStyle(sideBarContentColor)
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

    private var rowBackground: some View {
        ZStack(alignment: .leading) {
            cardShape
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
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
        return colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.black.opacity(0.24)
    }

    private var sideBarContentColor: Color {
        sideBarIsDark ? .white.opacity(0.95) : .black.opacity(0.78)
    }

    private var sideBarIsDark: Bool {
        if let pinboard = primaryAssignedPinboard {
            let color = NSColor(hex: pinboard.colorHex).usingColorSpace(.sRGB) ?? NSColor(hex: pinboard.colorHex)
            let luminance = (0.2126 * color.redComponent)
                + (0.7152 * color.greenComponent)
                + (0.0722 * color.blueComponent)
            return luminance < 0.58
        }
        return colorScheme == .dark
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.prefix(maxVisibleRows).enumerated()), id: \.offset) { index, item in
                ItemCompactRowDragPreview(item: item, pinboards: pinboards, width: width)
                    .frame(width: width, height: 70)
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
