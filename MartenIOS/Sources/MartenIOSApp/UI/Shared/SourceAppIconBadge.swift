import Foundation
import SwiftUI

public struct SourceAppIconBadge: View {
    public let bundleID: String?
    public let appName: String?
    public let iconData: Data?
    public var size: CGFloat = 30
    public var showBackground: Bool = true

    @State private var remoteIcon: PlatformImage?
    private static let martenIconData = MartenSourceIdentity.iconData(for: [Bundle.main])

    public init(bundleID: String?, appName: String?, iconData: Data?, size: CGFloat = 30, showBackground: Bool = true) {
        self.bundleID = bundleID
        self.appName = appName
        self.iconData = iconData
        self.size = size
        self.showBackground = showBackground
    }

    private var descriptor: SourceAppIconDescriptor {
        SourceAppIconDescriptor.resolve(bundleID: bundleID, appName: appName)
    }

    private var normalizedBundleID: String? {
        guard let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return nil
        }
        return bundleID.lowercased()
    }

    private var embeddedIcon: PlatformImage? {
        guard !isMarten else { return nil }
        guard let iconData, !iconData.isEmpty else { return nil }
        #if canImport(UIKit)
        return UIImage(data: iconData)
        #elseif canImport(AppKit)
        return NSImage(data: iconData)
        #endif
    }

    private var isMarten: Bool {
        SourceAppIconDescriptor.isMartenSource(bundleID: bundleID, appName: appName)
    }

    private var martenIcon: PlatformImage? {
        guard isMarten else { return nil }
        guard let iconData = Self.martenIconData, !iconData.isEmpty else { return nil }
        #if canImport(UIKit)
        return UIImage(data: iconData)
        #elseif canImport(AppKit)
        return NSImage(data: iconData)
        #endif
    }

    public var body: some View {
        let bundleID = normalizedBundleID

        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(descriptor.backgroundColor)
            }

            if let martenIcon {
                remoteIconView(martenIcon)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else if let embeddedIcon {
                remoteIconView(embeddedIcon)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else if let remoteIcon {
                remoteIconView(remoteIcon)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                content()
                    .foregroundStyle(descriptor.foregroundColor)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Group {
                if showBackground {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(descriptor.foregroundColor.opacity(0.2), lineWidth: 0.5)
                }
            }
        )
        .accessibilityHidden(true)
        .task(id: taskID(bundleID: bundleID)) {
            remoteIcon = nil
            guard !isMarten else { return }
            guard embeddedIcon == nil else { return }
            guard let bundleID else { return }
            let loadedIcon = await SourceAppIconRepository.shared.icon(forBundleID: bundleID)
            guard !Task.isCancelled else { return }
            remoteIcon = loadedIcon
        }
    }

    private func taskID(bundleID: String?) -> String {
        let digest = iconDataDigest(iconData)
        return "\(bundleID ?? "none")|\(digest)"
    }

    private func iconDataDigest(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "nil" }
        return String(format: "%08X", SourceAppIconDescriptor.fnv1aHash(data))
    }

    @ViewBuilder
    private func content() -> some View {
        switch descriptor.content {
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: size * 0.54, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .monogram(let token):
            Text(token)
                .font(.system(size: size * 0.42, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textCase(.uppercase)
        case .generic:
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private func remoteIconView(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
        #endif
    }
}
