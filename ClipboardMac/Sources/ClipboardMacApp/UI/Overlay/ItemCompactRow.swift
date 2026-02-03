import AppKit
import ClipboardCore
import Foundation
import SwiftUI

struct ItemCompactRow: View {
    private static let compactTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private let cardCornerRadius: CGFloat = 12
    private let sideBarWidth: CGFloat = 38

    let item: ClipItem
    let pinboards: [Pinboard]
    let lockedPinboardIDs: Set<UUID>
    let isSelected: Bool
    let isEditing: Bool
    let allowPinning: Bool
    let clipItemEditor: any ClipItemEditing
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
    @Binding var previewItemID: NSManagedObjectID?
    @Binding var isPreviewPopoverPresented: Bool

    @State private var lastTapTime: Date?
    @State private var editTitle = ""
    @StateObject private var appColorLoader = AppIconColorLoader()
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isPreviewPresented = Binding(
            get: { isPreviewPopoverPresented && previewItemID == item.objectID },
            set: { newValue in
                if !newValue {
                    if previewItemID == item.objectID {
                        previewItemID = nil
                    }
                    isPreviewPopoverPresented = false
                }
            }
        )

        HStack(spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                titleView

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
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(rowBackground)
        .clipShape(cardShape)
        .contentShape(cardShape)
        .overlay(selectionBorder)
        .onTapGesture {
            handleTap()
        }
        .onAppear {
            appColorLoader.load(bundleID: item.sourceAppBundleID)
        }
        .onChange(of: item.sourceAppBundleID) { newValue, _ in
            appColorLoader.load(bundleID: newValue)
        }
        .popover(isPresented: isPreviewPresented, arrowEdge: .trailing) {
            OverlayItemPreview(
                item: item,
                allowPinning: allowPinning,
                pinboards: pinboards,
                lockedPinboardIDs: lockedPinboardIDs,
                clipItemEditor: clipItemEditor,
                onEdit: {
                    previewItemID = nil
                    isPreviewPopoverPresented = false
                    onEdit()
                },
                onPaste: {
                    onPaste()
                    previewItemID = nil
                    isPreviewPopoverPresented = false
                },
                onPastePlainText: {
                    onPastePlainText()
                    previewItemID = nil
                    isPreviewPopoverPresented = false
                },
                onCopy: {
                    onCopy()
                    previewItemID = nil
                    isPreviewPopoverPresented = false
                },
                onTogglePin: {
                    onTogglePin()
                },
                onMoveToPinboard: { pinboard in
                    onMoveToPinboard(pinboard)
                },
                onCreatePinboard: {
                    previewItemID = nil
                    isPreviewPopoverPresented = false
                    onCreatePinboard()
                },
                onDelete: {
                    onDelete()
                    previewItemID = nil
                    isPreviewPopoverPresented = false
                }
            )
            .frame(width: 560, height: 380)
        }
        .contextMenu {
            CardContextMenu(
                item: item,
                itemID: item.id,
                isPinned: item.isPinned,
                allowPinning: allowPinning,
                assignedPinboardIDs: assignedPinboardIDs,
                pinboards: pinboards,
                lockedPinboardIDs: lockedPinboardIDs,
                onPaste: onPaste,
                onPastePlainText: onPastePlainText,
                onTogglePin: onTogglePin,
                onCopy: onCopy,
                onMoveToPinboard: onMoveToPinboard,
                onCreatePinboard: onCreatePinboard,
                onEdit: onEdit,
                onRename: onRename,
                onDelete: onDelete
            )
        }
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityIdentifier("overlay.itemCompact.\(item.id.uuidString)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Single click to select, double click to paste")
        .accessibilityAddTraits(.isButton)
    }

    private var rightInfoColumn: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 4) {
                if item.isPinned && allowPinning {
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

            HStack(spacing: 5) {
                Text(rightSideMetric)
                Circle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3, height: 3)
                Text(timeAgoShort)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var leadingVisual: some View {
        ZStack {
            if let pinboard = primaryAssignedPinboard {
                if let signKind = PinboardSignResolver.resolve(pinboard.iconName) {
                    pinboardSignView(signKind)
                }
            } else {
                AppIconView(bundleID: item.sourceAppBundleID, size: 19)
            }
        }
        .frame(width: sideBarWidth, alignment: .center)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func pinboardSignView(_ signKind: PinboardSignKind) -> some View {
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

    private var accessibilityLabel: String {
        "\(titleText). \(subtitle ?? "")"
    }

    private var titleView: some View {
        Group {
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($isFocused)
                    .onSubmit {
                        onCommitRename(editTitle)
                    }
                    .onAppear {
                        editTitle = item.customTitle ?? titleText
                        isFocused = true
                    }
            } else {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    private var rowBackground: some View {
        ZStack(alignment: .leading) {
            cardShape
                .fill(
                    isSelected
                        ? Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.23 : 0.16)
                        : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
            Rectangle()
                .fill(sideBarColor)
                .frame(width: sideBarWidth)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    private var sideBarColor: Color {
        if let pinboardColor {
            return pinboardColor
        }
        if let appColor = appColorLoader.color {
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
        if let appColor = appColorLoader.color {
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

    private var pinboardColor: Color? {
        guard let pinboard = primaryAssignedPinboard else {
            return nil
        }
        return Color(hex: pinboard.colorHex, fallback: .gray)
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            cardShape
                .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
        }
    }

    private var assignedPinboardIDs: Set<UUID> {
        let assigned = item.pinboards?.filter { !$0.isSystemClipboard } ?? []
        return Set(assigned.map(\.id))
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

    private var timeAgoShort: String {
        Self.compactTimeFormatter.localizedString(for: item.createdAt, relativeTo: Date())
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
        case .richText:
            return "Rich"
        case .mixed:
            return "Mixed"
        default:
            return typeLabel
        }
    }

    private var rightSideMetric: String {
        switch item.itemTypeValue {
        case .text, .richText, .code:
            let count = item.primaryText?.count ?? 0
            return "\(count) ch"
        case .color:
            return "Color"
        default:
            if item.byteCount > 0 {
                return ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
            }
            return typeLabel
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

    private func handleTap() {
        let now = Date()
        if let lastTapTime, now.timeIntervalSince(lastTapTime) < 0.3 {
            onDoubleTap()
            self.lastTapTime = nil
        } else {
            onTap()
            self.lastTapTime = now
        }
    }
}
