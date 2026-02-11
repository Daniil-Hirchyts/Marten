import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public extension ClipItem {
    var plainTextContent: String? {
        if let plainRep = representations?.first(where: { $0.kindValue == .plainText }),
           let data = plainRep.textData,
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let rtfRep = representations?.first(where: { $0.kindValue == .rtf }),
           let data = rtfRep.textData,
           let attributed = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
            return attributed.string
        }

        if let htmlRep = representations?.first(where: { $0.kindValue == .html }),
           let data = htmlRep.textData,
           let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
           ) {
            return attributed.string
        }

        if itemTypeValue == .url, let text = primaryText {
            return text
        }

        return primaryText
    }
}
