import CoreData
import Foundation
import MartenCore

struct ItemCardPresentation: Identifiable {
    enum PreviewKind {
        case text
        case richText
        case code
        case link
        case image
        case file
        case color
        case mixed
    }

    let id: NSManagedObjectID
    let itemType: ItemType
    let previewKind: PreviewKind

    let title: String
    let snippet: String?
    let urlHost: String?
    let urlPath: String?
    let colorHex: String?
    let fileName: String?
    let fileSize: String?

    let headerSubtitle: String?
    let sourceAppBundleID: String?
    let sourceAppDisplayName: String?
    let sourceAppIconData: Data?
    let footerLeadingText: String
    let footerTrailingText: String
    let statsLabel: String

    // Legacy fields retained for compatibility with existing callers.
    let footerSource: String
    let footerDate: String
    let footerTitle: String

    let needsLinkPreview: Bool
    
    // Pinboard information
    let primaryPinboardColorHex: String?
    let primaryPinboardSign: String?

    init(item: ClipItem) {
        id = item.objectID
        itemType = item.itemTypeValue
        needsLinkPreview = item.needsLinkPreview

        let primaryText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = primaryText?.isEmpty == false ? primaryText : nil
        let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinboardInfo = Self.computePrimaryPinboard(for: item)

        title = customTitle?.isEmpty == false ? customTitle! : Self.defaultTitle(for: item)
        sourceAppBundleID = Self.normalizedSourceBundleID(for: item)
        sourceAppDisplayName = Self.sourceLabel(for: item)
        sourceAppIconData = item.sourceAppIconData

        switch item.itemTypeValue {
        case .text:
            previewKind = .text
            snippet = normalizedText
            urlHost = nil
            urlPath = nil
            colorHex = nil
            fileName = nil
            fileSize = Self.byteCountString(for: item.byteCount)
        case .richText:
            previewKind = .richText
            snippet = item.plainTextContent ?? normalizedText
            urlHost = nil
            urlPath = nil
            colorHex = nil
            fileName = nil
            fileSize = Self.byteCountString(for: item.byteCount)
        case .code:
            previewKind = .code
            snippet = normalizedText
            urlHost = nil
            urlPath = nil
            colorHex = nil
            fileName = nil
            fileSize = Self.byteCountString(for: item.byteCount)
        case .url:
            previewKind = .link
            if let previewTitle = item.linkPreview?.title, !previewTitle.isEmpty {
                snippet = previewTitle
            } else {
                snippet = normalizedText
            }
            let parsedURL = normalizedText.flatMap(URL.init(string:))
            urlHost = item.linkPreview?.siteName ?? parsedURL?.host
            urlPath = parsedURL?.path.isEmpty == false ? parsedURL?.path : "/"
            colorHex = nil
            fileName = nil
            fileSize = nil
        case .image:
            previewKind = .image
            snippet = nil
            urlHost = nil
            urlPath = nil
            colorHex = nil
            fileName = nil
            fileSize = Self.byteCountString(for: item.byteCount)
        case .file:
            previewKind = .file
            snippet = nil
            urlHost = nil
            urlPath = nil
            colorHex = nil
            fileName = Self.fileName(for: item)
            fileSize = Self.byteCountString(for: item.byteCount)
        case .color:
            previewKind = .color
            let normalizedHex = normalizedText.flatMap(ColorHex.normalizedHex(from:))
            snippet = normalizedHex ?? normalizedText
            urlHost = nil
            urlPath = nil
            colorHex = normalizedHex
            fileName = nil
            fileSize = nil
        case .mixed:
            previewKind = .mixed
            snippet = normalizedText
            urlHost = nil
            urlPath = nil
            colorHex = nil
            fileName = nil
            fileSize = Self.byteCountString(for: item.byteCount)
        }

        statsLabel = Self.statsLabel(for: item)
        footerLeadingText = RelativeTime.short(from: item.modifiedAt)
        footerTrailingText = previewKind == .link ? (urlHost ?? "URL") : statsLabel
        headerSubtitle = pinboardInfo.name ?? sourceAppDisplayName

        footerSource = sourceAppDisplayName ?? "Unknown"
        footerDate = footerLeadingText
        footerTitle = normalizedText ?? title

        primaryPinboardColorHex = pinboardInfo.colorHex
        primaryPinboardSign = pinboardInfo.sign
    }

    private static func defaultTitle(for item: ClipItem) -> String {
        switch item.itemTypeValue {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .url:
            return "Link"
        case .code:
            return "Code"
        case .color:
            return "Color"
        case .mixed:
            return "Item"
        }
    }

    private static func byteCountString(for count: Int64) -> String? {
        guard count > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static func normalizedSourceBundleID(for item: ClipItem) -> String? {
        guard let bundleID = item.sourceAppBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return nil
        }
        return bundleID
    }

    private static func sourceLabel(for item: ClipItem) -> String? {
        if let sourceName = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceName.isEmpty {
            return sourceName
        }

        if let bundleID = normalizedSourceBundleID(for: item) {
            if let suffix = bundleID.split(separator: ".").last {
                return String(suffix)
            }
            return bundleID
        }

        return nil
    }

    private static func fileName(for item: ClipItem) -> String? {
        guard let representations = item.representations else { return nil }

        if let fileRep = representations.first(where: { $0.kindValue == .fileURL }),
            let textData = fileRep.textData,
            let path = String(data: textData, encoding: .utf8),
            !path.isEmpty
        {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        guard let primary = item.primaryText, !primary.isEmpty else { return nil }
        return URL(fileURLWithPath: primary).lastPathComponent
    }

    private static func statsLabel(for item: ClipItem) -> String {
        switch item.itemTypeValue {
        case .text, .richText, .code:
            let count = item.primaryText?.count ?? 0
            return "\(count) chars"
        case .color:
            return "Color"
        default:
            return byteCountString(for: item.byteCount) ?? defaultTitle(for: item)
        }
    }

    private static func computePrimaryPinboard(for item: ClipItem) -> (colorHex: String?, sign: String?, name: String?) {
        let pinboards = item.pinboards?.filter { !$0.isSystemMarten } ?? []
        let sorted = pinboards.sorted { $0.sortOrder < $1.sortOrder }
        guard let pinboard = sorted.first else { return (nil, nil, nil) }
        return (pinboard.colorHex, pinboard.iconName, pinboard.name)
    }
}
