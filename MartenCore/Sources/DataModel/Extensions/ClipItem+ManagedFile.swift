import Foundation

public extension ClipItem {
    var managedFileDisplayName: String? {
        ManagedFileAccess.displayName(for: self)
    }

    var managedFileExportName: String {
        let customRepresentation = representations?.first(where: { $0.kindValue == .custom })
        return ManagedFileAccess.exportFileName(
            for: self,
            fallbackExtension: customRepresentation?.fileExtension
        )
    }
}
