import Foundation

public struct ClipRepresentationPayload: Sendable {
    public let kind: RepresentationKind
    public let uti: String
    public let text: String?
    public let data: Data?
    public let fileExtension: String?
    public let displayOrder: Int16

    public init(
        kind: RepresentationKind,
        uti: String,
        text: String? = nil,
        data: Data? = nil,
        fileExtension: String? = nil,
        displayOrder: Int16 = 0
    ) {
        self.kind = kind
        self.uti = uti
        self.text = text
        self.data = data
        self.fileExtension = fileExtension
        self.displayOrder = displayOrder
    }

    public static func plainText(_ text: String, displayOrder: Int16 = 0)
        -> ClipRepresentationPayload
    {
        ClipRepresentationPayload(
            kind: .plainText,
            uti: "public.utf8-plain-text",
            text: text,
            displayOrder: displayOrder
        )
    }
}

public struct ClipItemPayload: Sendable {
    public let representations: [ClipRepresentationPayload]
    public let primaryText: String?
    public let itemType: ItemType
    public let needsLinkPreview: Bool
    public let isSensitive: Bool
    public let isTransient: Bool

    public init(
        representations: [ClipRepresentationPayload],
        primaryText: String?,
        itemType: ItemType,
        needsLinkPreview: Bool = false,
        isSensitive: Bool = false,
        isTransient: Bool = false
    ) {
        self.representations = representations
        self.primaryText = primaryText
        self.itemType = itemType
        self.needsLinkPreview = needsLinkPreview
        self.isSensitive = isSensitive
        self.isTransient = isTransient
    }
}
