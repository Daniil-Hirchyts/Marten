import SwiftUI

struct WatchItemRow: View {
    let item: WatchClipSummary
    var viewingPinboardID: UUID? = nil
    var pinboardLookup: [UUID: WatchPinboardSummary] = [:]
    var isCopied: Bool = false

    private var isEdgeToEdgeContent: Bool {
        item.itemType == .image
    }

    @ViewBuilder
    private var headerBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            
            if let pinboard = displayPinboard {
                let color = Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor)
                Rectangle()
                    .fill(color.opacity(0.35))
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.white.opacity(0.15))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                Text(item.displayTypeTitle)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let indicator = pinboardIndicator {
                    WatchPinboardIcon(iconName: indicator.iconName, tint: indicator.color)
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, WatchVisualSystem.cardPadding)
            .padding(.top, WatchVisualSystem.cardPadding + 2)
            .padding(.bottom, 6)
            .background(headerBackground)

            // Preview
            if isEdgeToEdgeContent {
                previewContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                previewContent
                    .padding(.horizontal, WatchVisualSystem.cardPadding)
                    .padding(.top, 8)
                    .padding(.bottom, WatchVisualSystem.cardPadding + 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: isEdgeToEdgeContent ? 0 : WatchVisualSystem.itemCardHeight,
            alignment: .topLeading
        )
        .contentShape(.rect)
        .clipShape(RoundedRectangle(cornerRadius: WatchVisualSystem.cornerRadius, style: .continuous))
        .overlay(
            WatchCardCopiedOverlay(isVisible: isCopied)
        )
    }

    var cardProminence: WatchCardProminence {
        if let pinboard = displayPinboard {
            return .tinted(Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor))
        }
        return .normal
    }

    private var pinboardIndicator: (name: String, iconName: String?, color: Color)? {
        guard let pinboard = displayPinboard else { return nil }
        let color = Color.watchColor(hex: pinboard.colorHex, fallback: .accentColor)
        return (pinboard.name, pinboard.iconName, color)
    }

    private var displayPinboard: WatchPinboardSummary? {
        if let viewingPinboardID, let pinboard = pinboardLookup[viewingPinboardID] {
            return pinboard
        }

        return item.pinboardIDs
            .compactMap { pinboardLookup[$0] }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .first
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.itemType {
        case .color:
            if let hex = item.colorHex {
                HStack(alignment: .center, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.watchColor(hex: hex, fallback: .gray))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)

                    Text(hex)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                defaultTextPreview
            }
        case .code:
            Text(item.preferredText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let path = item.thumbnailPath {
                WatchThumbnailImage(path: path)
                    .frame(height: 60) // Increased image size
            } else {
                defaultTextPreview
            }
        case .url:
            Text(item.preferredText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            defaultTextPreview
        }
    }

    private var defaultTextPreview: some View {
        let text = item.preferredText
        return Text(text.isEmpty ? item.subtitle : text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
