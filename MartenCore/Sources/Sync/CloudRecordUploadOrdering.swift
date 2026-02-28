import CloudKit
import Foundation

enum CloudRecordUploadOrdering {
    static func sortedForUpload<S: Sequence>(_ records: S) -> [CKRecord] where S.Element == CKRecord {
        records.sorted { lhs, rhs in
            let lhsPriority = priority(for: lhs)
            let rhsPriority = priority(for: rhs)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return lhs.recordID.recordName < rhs.recordID.recordName
        }
    }

    private static func priority(for record: CKRecord) -> Int {
        switch record.cloudRecordType {
        case .pinboard:
            return 0
        case .clipItem:
            return 1
        case .clipRepresentation:
            return 2
        case .linkPreview:
            return 3
        case .pinboardMembership:
            return 4
        case nil:
            return 5
        }
    }
}
