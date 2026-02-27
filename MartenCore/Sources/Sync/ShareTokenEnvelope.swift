import CloudKit
import Foundation

struct ShareTokenEnvelope: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let shareRecordName: String
    let rootRecordName: String
    let zoneName: String
    let zoneOwnerName: String
    let isOwner: Bool
    let accessControlRaw: Int16
    let defaultPermissionRaw: Int16
    let shareURL: String?

    init(
        shareRecordName: String,
        rootRecordName: String,
        zoneName: String,
        zoneOwnerName: String,
        isOwner: Bool,
        accessControlRaw: Int16,
        defaultPermissionRaw: Int16,
        shareURL: String?
    ) {
        self.version = Self.currentVersion
        self.shareRecordName = shareRecordName
        self.rootRecordName = rootRecordName
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.isOwner = isOwner
        self.accessControlRaw = accessControlRaw
        self.defaultPermissionRaw = defaultPermissionRaw
        self.shareURL = shareURL
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: isOwner ? CKCurrentUserDefaultName : zoneOwnerName
        )
    }

    func encodedString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from rawValue: String) -> ShareTokenEnvelope? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let envelope = try? JSONDecoder().decode(ShareTokenEnvelope.self, from: data) else {
            return nil
        }
        guard envelope.version == currentVersion else { return nil }
        guard envelope.isValid else { return nil }
        return envelope
    }

    private var isValid: Bool {
        !shareRecordName.isEmpty
            && !rootRecordName.isEmpty
            && !zoneName.isEmpty
            && !zoneOwnerName.isEmpty
    }
}
