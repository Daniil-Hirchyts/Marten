import Foundation
import MartenCore

extension ClipItem {
    var shouldUseLargePreviewPopover: Bool {
        if itemTypeValue == .url {
            return true
        }

        guard itemTypeValue == .file else {
            return false
        }

        return previewPopoverFileURL != nil
    }

    private var previewPopoverFileURL: URL? {
        guard let fileURL = FileURLAccessResolver.resolvedFileURL(from: self) else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }
}
