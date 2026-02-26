import CoreData
import Foundation

@objc(ClipItem)
public class ClipItem: NSManagedObject {
}

public enum ClipItemHashError: Error {
    case missingContent
}

public extension ClipItem {
    var itemTypeValue: ItemType {
        get {
            let storedType = ItemType(rawValue: itemType) ?? .text
            return storedType == .richText ? .text : storedType
        }
        set {
            let normalizedType: ItemType = newValue == .richText ? .text : newValue
            itemType = normalizedType.rawValue
        }
    }

    var hasMultipleRepresentations: Bool {
        return (representations?.count ?? 0) > 1
    }

    func computeCanonicalHash() throws -> String {
        if let primaryText, !primaryText.isEmpty {
            return Data(primaryText.utf8).sha256Hex()
        }

        let primaryRep = representations?
            .sorted { $0.displayOrder < $1.displayOrder }
            .first

        if let textData = primaryRep?.textData {
            return textData.sha256Hex()
        }

        if let binaryData = primaryRep?.binaryData {
            return binaryData.sha256Hex()
        }

        if let assetRef = primaryRep?.assetRef {
            return Data(assetRef.uuidString.utf8).sha256Hex()
        }

        throw ClipItemHashError.missingContent
    }
}
