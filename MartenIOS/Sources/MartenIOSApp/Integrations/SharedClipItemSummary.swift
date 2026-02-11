import Foundation
import MartenCore

public struct SharedClipItemSummary: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let itemType: ItemType
    public let primaryText: String?
    public let plainText: String?
    public let sourceAppName: String?
    public let sourceAppBundleID: String?
    public let pinboardIDs: [UUID]

    public init(
        id: UUID,
        createdAt: Date,
        itemType: ItemType,
        primaryText: String?,
        plainText: String?,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        pinboardIDs: [UUID]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.itemType = itemType
        self.primaryText = primaryText
        self.plainText = plainText
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.pinboardIDs = pinboardIDs
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
    public let isSystemMarten: Bool
    public let isShared: Bool
    public let canMakeChanges: Bool

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        isSystemMarten: Bool,
        isShared: Bool,
        canMakeChanges: Bool
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isSystemMarten = isSystemMarten
        self.isShared = isShared
        self.canMakeChanges = canMakeChanges
    }
}
