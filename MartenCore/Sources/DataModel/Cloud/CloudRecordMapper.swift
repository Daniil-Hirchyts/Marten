import CloudKit
import CoreData
import Foundation

// MARK: - Mapping Errors

/// Errors that can occur during cloud record mapping.
public enum CloudRecordMappingError: Error, LocalizedError {
    case missingRequiredField(field: String, recordType: String)
    case invalidFieldType(field: String, expected: String, actual: String)
    case invalidUUID(field: String, value: String)
    case entityNotFound(type: String, id: UUID)
    case contextMismatch
    case unsupportedRecordType(String)

    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field, let recordType):
            return "Missing required field '\(field)' in \(recordType) record"
        case .invalidFieldType(let field, let expected, let actual):
            return "Invalid type for field '\(field)': expected \(expected), got \(actual)"
        case .invalidUUID(let field, let value):
            return "Invalid UUID for field '\(field)': \(value)"
        case .entityNotFound(let type, let id):
            return "\(type) with id \(id.uuidString) not found"
        case .contextMismatch:
            return "Core Data context mismatch during mapping"
        case .unsupportedRecordType(let type):
            return "Unsupported record type: \(type)"
        }
    }
}

// MARK: - Cloud Record Mapper

/// Maps between Core Data entities and CloudKit records.
///
/// This class provides bidirectional mapping:
/// - Entity → CKRecord for uploading local changes
/// - CKRecord → Entity for applying remote changes
public final class CloudRecordMapper {
    private let zoneID: CKRecordZone.ID
    private let maxPrimaryTextLength = 10_000

    public init(zoneID: CKRecordZone.ID) {
        self.zoneID = zoneID
    }

    // MARK: - ClipItem Mapping

    /// Maps a ClipItem entity to a CKRecord.
    public func mapToRecord(_ item: ClipItem) -> CKRecord {
        let record = CKRecord.clipItem(id: item.id, zoneID: zoneID)

        record.setUUID(item.id, for: ClipItemField.id.rawValue)
        record.setDate(item.createdAt, for: ClipItemField.createdAt.rawValue)
        record.setDate(item.modifiedAt, for: ClipItemField.modifiedAt.rawValue)
        record.setString(item.sourceAppBundleID, for: ClipItemField.sourceAppBundleID.rawValue)
        record.setString(item.sourceAppName, for: ClipItemField.sourceAppName.rawValue)
        record.setItemType(item.itemTypeValue, for: ClipItemField.itemType.rawValue)

        // Truncate primary text to max length
        if let primaryText = item.primaryText {
            let truncated = String(primaryText.prefix(maxPrimaryTextLength))
            record.setString(truncated, for: ClipItemField.primaryText.rawValue)
        }

        record.setString(item.contentHash, for: ClipItemField.contentHash.rawValue)
        record.setBool(item.isSensitive, for: ClipItemField.isSensitive.rawValue)
        record.setBool(item.isTransient, for: ClipItemField.isTransient.rawValue)
        record.setBool(item.isPinned, for: ClipItemField.isPinned.rawValue)
        record.setInt64(item.byteCount, for: ClipItemField.byteCount.rawValue)
        record.setString(item.lastModifiedBy, for: ClipItemField.lastModifiedBy.rawValue)
        record.setDate(item.lastModifiedAt, for: ClipItemField.lastModifiedAt.rawValue)

        return record
    }

    /// Maps a ClipItem entity to a CKRecord in a specific zone.
    public func mapToRecord(_ item: ClipItem, zoneID targetZoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.clipItemID(item.id, zoneID: targetZoneID)
        let record = CKRecord(recordType: CloudRecordType.clipItem.rawValue, recordID: recordID)

        record.setUUID(item.id, for: ClipItemField.id.rawValue)
        record.setDate(item.createdAt, for: ClipItemField.createdAt.rawValue)
        record.setDate(item.modifiedAt, for: ClipItemField.modifiedAt.rawValue)
        record.setString(item.sourceAppBundleID, for: ClipItemField.sourceAppBundleID.rawValue)
        record.setString(item.sourceAppName, for: ClipItemField.sourceAppName.rawValue)
        record.setItemType(item.itemTypeValue, for: ClipItemField.itemType.rawValue)

        if let primaryText = item.primaryText {
            let truncated = String(primaryText.prefix(maxPrimaryTextLength))
            record.setString(truncated, for: ClipItemField.primaryText.rawValue)
        }

        record.setString(item.contentHash, for: ClipItemField.contentHash.rawValue)
        record.setBool(item.isSensitive, for: ClipItemField.isSensitive.rawValue)
        record.setBool(item.isTransient, for: ClipItemField.isTransient.rawValue)
        record.setBool(item.isPinned, for: ClipItemField.isPinned.rawValue)
        record.setInt64(item.byteCount, for: ClipItemField.byteCount.rawValue)
        record.setString(item.lastModifiedBy, for: ClipItemField.lastModifiedBy.rawValue)
        record.setDate(item.lastModifiedAt, for: ClipItemField.lastModifiedAt.rawValue)

        return record
    }

    /// Maps a Pinboard entity to a CKRecord in a specific zone.
    public func mapToRecord(_ pinboard: Pinboard, zoneID targetZoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID.pinboardID(pinboard.id, zoneID: targetZoneID)
        let record = CKRecord(recordType: CloudRecordType.pinboard.rawValue, recordID: recordID)

        record.setUUID(pinboard.id, for: PinboardField.id.rawValue)
        record.setString(pinboard.name, for: PinboardField.name.rawValue)
        record.setString(pinboard.colorHex, for: PinboardField.colorHex.rawValue)
        record.setInt16(pinboard.sortOrder, for: PinboardField.sortOrder.rawValue)
        record.setBool(pinboard.isSystemMarten, for: PinboardField.isSystemMarten.rawValue)
        record.setDate(pinboard.createdAt, for: PinboardField.createdAt.rawValue)
        record.setDate(Date(), for: PinboardField.modifiedAt.rawValue)
        record.setString(pinboard.iconName, for: PinboardField.iconName.rawValue)

        return record
    }

    /// Updates an existing ClipItem entity from a CKRecord.
    public func updateEntity(_ item: ClipItem, from record: CKRecord) throws {
        let missingFields = record.validateClipItemFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.clipItem.rawValue
            )
        }

        // Only update if record is newer
        if let recordModifiedAt = record.date(for: ClipItemField.modifiedAt.rawValue),
           recordModifiedAt > item.modifiedAt {
            applyClipItemFields(to: item, from: record)
        }
    }

    /// Creates a new ClipItem entity from a CKRecord.
    public func createClipItem(from record: CKRecord, in context: NSManagedObjectContext) throws -> ClipItem {
        let missingFields = record.validateClipItemFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.clipItem.rawValue
            )
        }

        guard let item = NSEntityDescription.insertNewObject(
            forEntityName: "ClipItem",
            into: context
        ) as? ClipItem else {
            throw CloudRecordMappingError.contextMismatch
        }

        applyClipItemFields(to: item, from: record)
        return item
    }

    private func applyClipItemFields(to item: ClipItem, from record: CKRecord) {
        if let id = record.uuid(for: ClipItemField.id.rawValue) {
            item.id = id
        }
        if let createdAt = record.date(for: ClipItemField.createdAt.rawValue) {
            item.createdAt = createdAt
        }
        if let modifiedAt = record.date(for: ClipItemField.modifiedAt.rawValue) {
            item.modifiedAt = modifiedAt
        }

        item.sourceAppBundleID = record.string(for: ClipItemField.sourceAppBundleID.rawValue)
        item.sourceAppName = record.string(for: ClipItemField.sourceAppName.rawValue)

        if let itemType = record.itemType(for: ClipItemField.itemType.rawValue) {
            item.itemTypeValue = itemType
        }

        item.primaryText = record.string(for: ClipItemField.primaryText.rawValue)

        if let contentHash = record.string(for: ClipItemField.contentHash.rawValue) {
            item.contentHash = contentHash
        }

        item.isSensitive = record.bool(for: ClipItemField.isSensitive.rawValue)
        item.isTransient = record.bool(for: ClipItemField.isTransient.rawValue)
        item.isPinned = record.bool(for: ClipItemField.isPinned.rawValue)

        if let byteCount = record.int64(for: ClipItemField.byteCount.rawValue) {
            item.byteCount = byteCount
        }

        item.lastModifiedBy = record.string(for: ClipItemField.lastModifiedBy.rawValue)
        item.lastModifiedAt = record.date(for: ClipItemField.lastModifiedAt.rawValue)

        // Calculate displayOrder from modifiedAt
        if let modifiedAt = record.date(for: ClipItemField.modifiedAt.rawValue) {
            item.displayOrder = Int64(modifiedAt.timeIntervalSince1970 * 1000)
        }
    }

    // MARK: - ClipRepresentation Mapping

    /// Maps a ClipRepresentation entity to a CKRecord.
    public func mapToRecord(_ representation: ClipRepresentation, parentItemID: UUID) -> CKRecord {
        let record = CKRecord.clipRepresentation(id: representation.id, zoneID: zoneID)

        record.setUUID(representation.id, for: ClipRepresentationField.id.rawValue)
        record.setUUID(parentItemID, for: ClipRepresentationField.clipItemID.rawValue)

        // Set parent reference for cascade delete
        let parentRecordID = CKRecord.ID.clipItemID(parentItemID, zoneID: zoneID)
        record.setParentReference(to: parentRecordID, for: ClipRepresentationField.clipItemRef.rawValue)

        record.setString(representation.uti, for: ClipRepresentationField.uti.rawValue)
        record.setRepresentationKind(representation.kindValue, for: ClipRepresentationField.kind.rawValue)
        record.setInt16(representation.displayOrder, for: ClipRepresentationField.displayOrder.rawValue)

        // Store text data directly if present
        if let textData = representation.textData, let text = String(data: textData, encoding: .utf8) {
            record.setString(text, for: ClipRepresentationField.textData.rawValue)
        }

        record.setInt64(representation.byteCount, for: ClipRepresentationField.byteCount.rawValue)
        record.setDate(Date(), for: ClipRepresentationField.modifiedAt.rawValue)

        return record
    }

    /// Updates an existing ClipRepresentation entity from a CKRecord.
    public func updateEntity(_ representation: ClipRepresentation, from record: CKRecord) throws {
        let missingFields = record.validateClipRepresentationFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.clipRepresentation.rawValue
            )
        }

        applyClipRepresentationFields(to: representation, from: record)
    }

    /// Creates a new ClipRepresentation entity from a CKRecord.
    public func createClipRepresentation(
        from record: CKRecord,
        in context: NSManagedObjectContext
    ) throws -> ClipRepresentation {
        let missingFields = record.validateClipRepresentationFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.clipRepresentation.rawValue
            )
        }

        guard let representation = NSEntityDescription.insertNewObject(
            forEntityName: "ClipRepresentation",
            into: context
        ) as? ClipRepresentation else {
            throw CloudRecordMappingError.contextMismatch
        }

        applyClipRepresentationFields(to: representation, from: record)
        return representation
    }

    private func applyClipRepresentationFields(to representation: ClipRepresentation, from record: CKRecord) {
        if let id = record.uuid(for: ClipRepresentationField.id.rawValue) {
            representation.id = id
        }
        if let uti = record.string(for: ClipRepresentationField.uti.rawValue) {
            representation.uti = uti
        }
        if let kind = record.representationKind(for: ClipRepresentationField.kind.rawValue) {
            representation.kindValue = kind
        }
        if let displayOrder = record.int16(for: ClipRepresentationField.displayOrder.rawValue) {
            representation.displayOrder = displayOrder
        }
        if let textString = record.string(for: ClipRepresentationField.textData.rawValue) {
            representation.textData = Data(textString.utf8)
        }
        if let byteCount = record.int64(for: ClipRepresentationField.byteCount.rawValue) {
            representation.byteCount = byteCount
        }
    }

    // MARK: - Pinboard Mapping

    /// Maps a Pinboard entity to a CKRecord.
    public func mapToRecord(_ pinboard: Pinboard) -> CKRecord {
        let record = CKRecord.pinboard(id: pinboard.id, zoneID: zoneID)

        record.setUUID(pinboard.id, for: PinboardField.id.rawValue)
        record.setString(pinboard.name, for: PinboardField.name.rawValue)
        record.setString(pinboard.colorHex, for: PinboardField.colorHex.rawValue)
        record.setInt16(pinboard.sortOrder, for: PinboardField.sortOrder.rawValue)
        record.setBool(pinboard.isSystemMarten, for: PinboardField.isSystemMarten.rawValue)
        record.setDate(pinboard.createdAt, for: PinboardField.createdAt.rawValue)
        record.setDate(Date(), for: PinboardField.modifiedAt.rawValue)
        record.setString(pinboard.iconName, for: PinboardField.iconName.rawValue)

        return record
    }

    /// Updates an existing Pinboard entity from a CKRecord.
    public func updateEntity(_ pinboard: Pinboard, from record: CKRecord) throws {
        let missingFields = record.validatePinboardFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.pinboard.rawValue
            )
        }

        applyPinboardFields(to: pinboard, from: record)
    }

    /// Creates a new Pinboard entity from a CKRecord.
    public func createPinboard(from record: CKRecord, in context: NSManagedObjectContext) throws -> Pinboard {
        let missingFields = record.validatePinboardFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.pinboard.rawValue
            )
        }

        guard let pinboard = NSEntityDescription.insertNewObject(
            forEntityName: "Pinboard",
            into: context
        ) as? Pinboard else {
            throw CloudRecordMappingError.contextMismatch
        }

        applyPinboardFields(to: pinboard, from: record)
        return pinboard
    }

    private func applyPinboardFields(to pinboard: Pinboard, from record: CKRecord) {
        if let id = record.uuid(for: PinboardField.id.rawValue) {
            pinboard.id = id
        }
        if let name = record.string(for: PinboardField.name.rawValue) {
            pinboard.name = name
        }
        if let colorHex = record.string(for: PinboardField.colorHex.rawValue) {
            pinboard.colorHex = colorHex
        }
        if let sortOrder = record.int16(for: PinboardField.sortOrder.rawValue) {
            pinboard.sortOrder = sortOrder
        }

        pinboard.isSystemMarten = record.bool(for: PinboardField.isSystemMarten.rawValue)

        if let createdAt = record.date(for: PinboardField.createdAt.rawValue) {
            pinboard.createdAt = createdAt
        }

        pinboard.iconName = record.string(for: PinboardField.iconName.rawValue)
    }

    // MARK: - PinboardMembership Mapping

    /// Represents a pinboard membership for mapping purposes.
    public struct PinboardMembershipData: Equatable, Sendable {
        public let id: UUID
        public let clipItemID: UUID
        public let pinboardID: UUID
        public let addedAt: Date
        public let modifiedAt: Date

        public init(id: UUID, clipItemID: UUID, pinboardID: UUID, addedAt: Date = Date(), modifiedAt: Date = Date()) {
            self.id = id
            self.clipItemID = clipItemID
            self.pinboardID = pinboardID
            self.addedAt = addedAt
            self.modifiedAt = modifiedAt
        }
    }

    /// Maps a PinboardMembership to a CKRecord.
    public func mapToRecord(_ membership: PinboardMembershipData) -> CKRecord {
        let record = CKRecord.pinboardMembership(id: membership.id, zoneID: zoneID)

        record.setUUID(membership.id, for: PinboardMembershipField.id.rawValue)
        record.setUUID(membership.clipItemID, for: PinboardMembershipField.clipItemID.rawValue)
        record.setUUID(membership.pinboardID, for: PinboardMembershipField.pinboardID.rawValue)
        record.setDate(membership.addedAt, for: PinboardMembershipField.addedAt.rawValue)
        record.setDate(membership.modifiedAt, for: PinboardMembershipField.modifiedAt.rawValue)

        return record
    }

    /// Creates PinboardMembershipData from a CKRecord.
    public func createPinboardMembershipData(from record: CKRecord) throws -> PinboardMembershipData {
        let missingFields = record.validatePinboardMembershipFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.pinboardMembership.rawValue
            )
        }

        guard let id = record.uuid(for: PinboardMembershipField.id.rawValue),
              let clipItemID = record.uuid(for: PinboardMembershipField.clipItemID.rawValue),
              let pinboardID = record.uuid(for: PinboardMembershipField.pinboardID.rawValue) else {
            throw CloudRecordMappingError.missingRequiredField(
                field: "id, clipItemID, or pinboardID",
                recordType: CloudRecordType.pinboardMembership.rawValue
            )
        }

        return PinboardMembershipData(
            id: id,
            clipItemID: clipItemID,
            pinboardID: pinboardID,
            addedAt: record.date(for: PinboardMembershipField.addedAt.rawValue) ?? Date(),
            modifiedAt: record.date(for: PinboardMembershipField.modifiedAt.rawValue) ?? Date()
        )
    }

    // MARK: - LinkPreview Mapping

    /// Maps a LinkPreview entity to a CKRecord.
    public func mapToRecord(_ preview: LinkPreview, parentItemID: UUID) -> CKRecord {
        let record = CKRecord.linkPreview(id: preview.id, zoneID: zoneID)

        record.setUUID(preview.id, for: LinkPreviewField.id.rawValue)
        record.setUUID(parentItemID, for: LinkPreviewField.clipItemID.rawValue)

        // Set parent reference for cascade delete
        let parentRecordID = CKRecord.ID.clipItemID(parentItemID, zoneID: zoneID)
        record.setParentReference(to: parentRecordID, for: LinkPreviewField.clipItemRef.rawValue)

        record.setString(preview.url, for: LinkPreviewField.url.rawValue)
        record.setString(preview.title, for: LinkPreviewField.title.rawValue)
        record.setString(preview.summary, for: LinkPreviewField.summary.rawValue)
        record.setString(preview.siteName, for: LinkPreviewField.siteName.rawValue)
        record.setDate(preview.fetchedAt, for: LinkPreviewField.fetchedAt.rawValue)

        return record
    }

    /// Updates an existing LinkPreview entity from a CKRecord.
    public func updateEntity(_ preview: LinkPreview, from record: CKRecord) throws {
        let missingFields = record.validateLinkPreviewFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.linkPreview.rawValue
            )
        }

        applyLinkPreviewFields(to: preview, from: record)
    }

    /// Creates a new LinkPreview entity from a CKRecord.
    public func createLinkPreview(from record: CKRecord, in context: NSManagedObjectContext) throws -> LinkPreview {
        let missingFields = record.validateLinkPreviewFields()
        if !missingFields.isEmpty {
            throw CloudRecordMappingError.missingRequiredField(
                field: missingFields.joined(separator: ", "),
                recordType: CloudRecordType.linkPreview.rawValue
            )
        }

        guard let preview = NSEntityDescription.insertNewObject(
            forEntityName: "LinkPreview",
            into: context
        ) as? LinkPreview else {
            throw CloudRecordMappingError.contextMismatch
        }

        applyLinkPreviewFields(to: preview, from: record)
        return preview
    }

    private func applyLinkPreviewFields(to preview: LinkPreview, from record: CKRecord) {
        if let id = record.uuid(for: LinkPreviewField.id.rawValue) {
            preview.id = id
        }
        if let url = record.string(for: LinkPreviewField.url.rawValue) {
            preview.url = url
        }

        preview.title = record.string(for: LinkPreviewField.title.rawValue)
        preview.summary = record.string(for: LinkPreviewField.summary.rawValue)
        preview.siteName = record.string(for: LinkPreviewField.siteName.rawValue)

        if let fetchedAt = record.date(for: LinkPreviewField.fetchedAt.rawValue) {
            preview.fetchedAt = fetchedAt
        }
    }

    // MARK: - Generic Record Processing

    /// Processes any CKRecord and returns the record type.
    public func identifyRecordType(_ record: CKRecord) -> CloudRecordType? {
        CloudRecordType(rawValue: record.recordType)
    }

    /// Extracts the parent ClipItem ID from a child record (representation or link preview).
    public func extractParentClipItemID(from record: CKRecord) -> UUID? {
        // Try clipItemID field first
        if let id = record.uuid(for: ClipRepresentationField.clipItemID.rawValue) {
            return id
        }
        if let id = record.uuid(for: LinkPreviewField.clipItemID.rawValue) {
            return id
        }

        // Try reference field
        if let ref = record.reference(for: ClipRepresentationField.clipItemRef.rawValue) {
            return ref.recordID.extractUUID()
        }
        if let ref = record.reference(for: LinkPreviewField.clipItemRef.rawValue) {
            return ref.recordID.extractUUID()
        }

        return nil
    }
}

// MARK: - Batch Mapping Helpers

public extension CloudRecordMapper {
    /// Maps multiple ClipItems to CKRecords.
    func mapItemsToRecords(_ items: [ClipItem]) -> [CKRecord] {
        items.map { mapToRecord($0) }
    }

    /// Maps a ClipItem and all its representations to CKRecords.
    func mapItemWithRepresentations(_ item: ClipItem) -> [CKRecord] {
        var records: [CKRecord] = [mapToRecord(item)]

        if let representations = item.representations {
            for representation in representations {
                records.append(mapToRecord(representation, parentItemID: item.id))
            }
        }

        if let linkPreview = item.linkPreview {
            records.append(mapToRecord(linkPreview, parentItemID: item.id))
        }

        return records
    }

    /// Maps all pinboard memberships for an item.
    func mapPinboardMemberships(for item: ClipItem) -> [CKRecord] {
        guard let pinboards = item.pinboards else { return [] }

        return pinboards.compactMap { pinboard -> CKRecord? in
            // Skip system clipboard pinboard
            guard !pinboard.isSystemMarten else { return nil }

            let membership = PinboardMembershipData(
                id: UUID(),
                clipItemID: item.id,
                pinboardID: pinboard.id
            )
            return mapToRecord(membership)
        }
    }
}
