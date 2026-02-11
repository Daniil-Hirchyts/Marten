import CloudKit
import Foundation

// MARK: - CloudKit Record Types

/// CloudKit record type identifiers matching the schema.
public enum CloudRecordType: String {
    case clipItem = "CKClipItem"
    case clipRepresentation = "CKClipRepresentation"
    case pinboard = "CKPinboard"
    case pinboardMembership = "CKPinboardMembership"
    case linkPreview = "CKLinkPreview"
}

// MARK: - Record ID Helpers

public extension CKRecord.ID {
    /// Creates a record ID for a ClipItem.
    static func clipItemID(_ uuid: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "ClipItem-\(uuid.uuidString)", zoneID: zoneID)
    }

    /// Creates a record ID for a ClipRepresentation.
    static func clipRepresentationID(_ uuid: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "ClipRep-\(uuid.uuidString)", zoneID: zoneID)
    }

    /// Creates a record ID for a Pinboard.
    static func pinboardID(_ uuid: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "Pinboard-\(uuid.uuidString)", zoneID: zoneID)
    }

    /// Creates a record ID for a PinboardMembership.
    static func membershipID(_ uuid: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "Membership-\(uuid.uuidString)", zoneID: zoneID)
    }

    /// Creates a record ID for a LinkPreview.
    static func linkPreviewID(_ uuid: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "LinkPreview-\(uuid.uuidString)", zoneID: zoneID)
    }

    /// Creates a zone ID for a shared pinboard.
    static func sharedPinboardZoneID(_ pinboardUUID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "SharedPinboard-\(pinboardUUID.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    /// Extracts the UUID from a record name with a prefix.
    func extractUUID() -> UUID? {
        let components = recordName.split(separator: "-", maxSplits: 1)
        guard components.count == 2, let uuid = UUID(uuidString: String(components[1])) else {
            return nil
        }
        return uuid
    }
}

// MARK: - Type-Safe Field Keys

/// Field keys for CKClipItem records.
public enum ClipItemField: String {
    case id
    case createdAt
    case modifiedAt
    case sourceAppBundleID
    case sourceAppName
    case itemType
    case primaryText
    case contentHash
    case isSensitive
    case isTransient
    case isPinned
    case thumbnailAsset
    case byteCount
    case lastModifiedBy
    case lastModifiedAt
}

/// Field keys for CKClipRepresentation records.
public enum ClipRepresentationField: String {
    case id
    case clipItemID
    case clipItemRef
    case uti
    case kind
    case displayOrder
    case textData
    case asset
    case byteCount
    case modifiedAt
}

/// Field keys for CKPinboard records.
public enum PinboardField: String {
    case id
    case name
    case colorHex
    case sortOrder
    case isSystemMarten
    case createdAt
    case modifiedAt
    case iconName
}

/// Field keys for CKPinboardMembership records.
public enum PinboardMembershipField: String {
    case id
    case clipItemID
    case pinboardID
    case addedAt
    case modifiedAt
}

/// Field keys for CKLinkPreview records.
public enum LinkPreviewField: String {
    case id
    case clipItemID
    case clipItemRef
    case url
    case title
    case summary
    case imageAsset
    case siteName
    case fetchedAt
}

// MARK: - CKRecord Type-Safe Extensions

public extension CKRecord {
    /// Gets the record type as a CloudRecordType enum.
    var cloudRecordType: CloudRecordType? {
        CloudRecordType(rawValue: recordType)
    }

    // MARK: - String Fields

    /// Gets a string value for a field, returning nil if not present.
    func string(for key: String) -> String? {
        self[key] as? String
    }

    /// Sets a string value for a field.
    func setString(_ value: String?, for key: String) {
        self[key] = value
    }

    // MARK: - UUID Fields

    /// Gets a UUID from a string field.
    func uuid(for key: String) -> UUID? {
        guard let string = self[key] as? String else { return nil }
        return UUID(uuidString: string)
    }

    /// Sets a UUID as a string field.
    func setUUID(_ value: UUID?, for key: String) {
        self[key] = value?.uuidString
    }

    // MARK: - Date Fields

    /// Gets a date value for a field.
    func date(for key: String) -> Date? {
        self[key] as? Date
    }

    /// Sets a date value for a field.
    func setDate(_ value: Date?, for key: String) {
        self[key] = value
    }

    // MARK: - Int64 Fields

    /// Gets an Int64 value for a field.
    func int64(for key: String) -> Int64? {
        self[key] as? Int64
    }

    /// Sets an Int64 value for a field.
    func setInt64(_ value: Int64, for key: String) {
        self[key] = value
    }

    // MARK: - Int16 Fields (via Int64)

    /// Gets an Int16 value from an Int64 field.
    func int16(for key: String) -> Int16? {
        guard let value = self[key] as? Int64 else { return nil }
        return Int16(clamping: value)
    }

    /// Sets an Int16 value as an Int64 field.
    func setInt16(_ value: Int16, for key: String) {
        self[key] = Int64(value)
    }

    // MARK: - Bool Fields (stored as Int64)

    /// Gets a boolean value from an Int64 field (0 = false, 1 = true).
    func bool(for key: String) -> Bool {
        (self[key] as? Int64 ?? 0) != 0
    }

    /// Sets a boolean value as an Int64 field.
    func setBool(_ value: Bool, for key: String) {
        self[key] = value ? Int64(1) : Int64(0)
    }

    // MARK: - Asset Fields

    /// Gets a CKAsset for a field.
    func asset(for key: String) -> CKAsset? {
        self[key] as? CKAsset
    }

    /// Sets a CKAsset for a field.
    func setAsset(_ value: CKAsset?, for key: String) {
        self[key] = value
    }

    // MARK: - Reference Fields

    /// Gets a CKRecord.Reference for a field.
    func reference(for key: String) -> CKRecord.Reference? {
        self[key] as? CKRecord.Reference
    }

    /// Sets a CKRecord.Reference for a field.
    func setReference(_ value: CKRecord.Reference?, for key: String) {
        self[key] = value
    }

    /// Creates and sets a parent reference that cascades deletes.
    func setParentReference(to parentRecordID: CKRecord.ID, for key: String) {
        let reference = CKRecord.Reference(recordID: parentRecordID, action: .deleteSelf)
        self[key] = reference
    }

    // MARK: - Enum Fields

    /// Gets an ItemType from an Int64 field.
    func itemType(for key: String) -> ItemType? {
        guard let rawValue = int16(for: key) else { return nil }
        return ItemType(rawValue: rawValue)
    }

    /// Sets an ItemType as an Int64 field.
    func setItemType(_ value: ItemType, for key: String) {
        setInt16(value.rawValue, for: key)
    }

    /// Gets a RepresentationKind from an Int64 field.
    func representationKind(for key: String) -> RepresentationKind? {
        guard let rawValue = int16(for: key) else { return nil }
        return RepresentationKind(rawValue: rawValue)
    }

    /// Sets a RepresentationKind as an Int64 field.
    func setRepresentationKind(_ value: RepresentationKind, for key: String) {
        setInt16(value.rawValue, for: key)
    }
}

// MARK: - Convenience Initializers

public extension CKRecord {
    /// Creates a new CKClipItem record.
    static func clipItem(id: UUID, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.clipItemID(id, zoneID: zoneID)
        return CKRecord(recordType: CloudRecordType.clipItem.rawValue, recordID: recordID)
    }

    /// Creates a new CKClipRepresentation record.
    static func clipRepresentation(id: UUID, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.clipRepresentationID(id, zoneID: zoneID)
        return CKRecord(recordType: CloudRecordType.clipRepresentation.rawValue, recordID: recordID)
    }

    /// Creates a new CKPinboard record.
    static func pinboard(id: UUID, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.pinboardID(id, zoneID: zoneID)
        return CKRecord(recordType: CloudRecordType.pinboard.rawValue, recordID: recordID)
    }

    /// Creates a new CKPinboardMembership record.
    static func pinboardMembership(id: UUID, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.membershipID(id, zoneID: zoneID)
        return CKRecord(recordType: CloudRecordType.pinboardMembership.rawValue, recordID: recordID)
    }

    /// Creates a new CKLinkPreview record.
    static func linkPreview(id: UUID, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.linkPreviewID(id, zoneID: zoneID)
        return CKRecord(recordType: CloudRecordType.linkPreview.rawValue, recordID: recordID)
    }
}

// MARK: - Validation Extensions

public extension CKRecord {
    /// Validates that required fields are present for a ClipItem record.
    func validateClipItemFields() -> [String] {
        var missingFields: [String] = []

        if uuid(for: ClipItemField.id.rawValue) == nil {
            missingFields.append(ClipItemField.id.rawValue)
        }
        if date(for: ClipItemField.createdAt.rawValue) == nil {
            missingFields.append(ClipItemField.createdAt.rawValue)
        }
        if date(for: ClipItemField.modifiedAt.rawValue) == nil {
            missingFields.append(ClipItemField.modifiedAt.rawValue)
        }
        if string(for: ClipItemField.contentHash.rawValue) == nil {
            missingFields.append(ClipItemField.contentHash.rawValue)
        }
        if itemType(for: ClipItemField.itemType.rawValue) == nil {
            missingFields.append(ClipItemField.itemType.rawValue)
        }

        return missingFields
    }

    /// Validates that required fields are present for a ClipRepresentation record.
    func validateClipRepresentationFields() -> [String] {
        var missingFields: [String] = []

        if uuid(for: ClipRepresentationField.id.rawValue) == nil {
            missingFields.append(ClipRepresentationField.id.rawValue)
        }
        if string(for: ClipRepresentationField.uti.rawValue) == nil {
            missingFields.append(ClipRepresentationField.uti.rawValue)
        }
        if representationKind(for: ClipRepresentationField.kind.rawValue) == nil {
            missingFields.append(ClipRepresentationField.kind.rawValue)
        }

        return missingFields
    }

    /// Validates that required fields are present for a Pinboard record.
    func validatePinboardFields() -> [String] {
        var missingFields: [String] = []

        if uuid(for: PinboardField.id.rawValue) == nil {
            missingFields.append(PinboardField.id.rawValue)
        }
        if string(for: PinboardField.name.rawValue) == nil {
            missingFields.append(PinboardField.name.rawValue)
        }
        if string(for: PinboardField.colorHex.rawValue) == nil {
            missingFields.append(PinboardField.colorHex.rawValue)
        }

        return missingFields
    }

    /// Validates that required fields are present for a PinboardMembership record.
    func validatePinboardMembershipFields() -> [String] {
        var missingFields: [String] = []

        if uuid(for: PinboardMembershipField.id.rawValue) == nil {
            missingFields.append(PinboardMembershipField.id.rawValue)
        }
        if uuid(for: PinboardMembershipField.clipItemID.rawValue) == nil {
            missingFields.append(PinboardMembershipField.clipItemID.rawValue)
        }
        if uuid(for: PinboardMembershipField.pinboardID.rawValue) == nil {
            missingFields.append(PinboardMembershipField.pinboardID.rawValue)
        }

        return missingFields
    }

    /// Validates that required fields are present for a LinkPreview record.
    func validateLinkPreviewFields() -> [String] {
        var missingFields: [String] = []

        if uuid(for: LinkPreviewField.id.rawValue) == nil {
            missingFields.append(LinkPreviewField.id.rawValue)
        }
        if string(for: LinkPreviewField.url.rawValue) == nil {
            missingFields.append(LinkPreviewField.url.rawValue)
        }

        return missingFields
    }
}
