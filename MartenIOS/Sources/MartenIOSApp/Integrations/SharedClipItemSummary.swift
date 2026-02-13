import Foundation
import MartenCore

public struct SharedClipItemSummary: Identifiable, Sendable, Equatable {
    public struct SharedLinkPreviewSummary: Sendable, Equatable {
        public let id: UUID
        public let title: String?
        public let siteName: String?
        public let imagePath: String?
        public let imageURL: String?
        public let fetchedAt: Date

        public init(
            id: UUID,
            title: String?,
            siteName: String?,
            imagePath: String?,
            imageURL: String?,
            fetchedAt: Date
        ) {
            self.id = id
            self.title = title
            self.siteName = siteName
            self.imagePath = imagePath
            self.imageURL = imageURL
            self.fetchedAt = fetchedAt
        }
    }

    public let id: UUID
    public let createdAt: Date
    public let modifiedAt: Date
    public let itemType: ItemType
    public let primaryText: String?
    public let plainText: String?
    public let sourceAppName: String?
    public let sourceAppBundleID: String?
    public let sourceAppIconData: Data?
    public let pinboardIDs: [UUID]
    public let byteCount: Int64
    public let thumbnailPath: String?
    public let fileName: String?
    public let colorHex: String?
    public let linkPreview: SharedLinkPreviewSummary?

    public init(
        id: UUID,
        createdAt: Date,
        modifiedAt: Date? = nil,
        itemType: ItemType,
        primaryText: String?,
        plainText: String?,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        sourceAppIconData: Data? = nil,
        pinboardIDs: [UUID],
        byteCount: Int64 = 0,
        thumbnailPath: String? = nil,
        fileName: String? = nil,
        colorHex: String? = nil,
        linkPreview: SharedLinkPreviewSummary? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.itemType = itemType
        self.primaryText = primaryText
        self.plainText = plainText
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppIconData = sourceAppIconData
        self.pinboardIDs = pinboardIDs
        self.byteCount = byteCount
        self.thumbnailPath = thumbnailPath
        self.fileName = fileName
        self.colorHex = colorHex
        self.linkPreview = linkPreview
    }

    public var insertionText: String {
        let base = plainText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return base
    }
}

public struct SharedPinboardSummary: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let iconName: String?
    public let isSystemMarten: Bool
    public let isShared: Bool
    public let canMakeChanges: Bool

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        iconName: String? = nil,
        isSystemMarten: Bool,
        isShared: Bool,
        canMakeChanges: Bool
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.isSystemMarten = isSystemMarten
        self.isShared = isShared
        self.canMakeChanges = canMakeChanges
    }
}
