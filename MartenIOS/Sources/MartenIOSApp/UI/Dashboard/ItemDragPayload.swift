import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ItemDragPayload: Codable, Hashable, Transferable {
    let objectURIStrings: [String]

    init(objectIDs: [NSManagedObjectID]) {
        objectURIStrings = objectIDs.map {
            $0.uriRepresentation().absoluteString
        }
    }

    var objectIDURIs: [URL] {
        objectURIStrings.compactMap(URL.init(string:))
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .martenItemDragPayload)
    }
}

private extension UTType {
    static let martenItemDragPayload = UTType(exportedAs: "com.hirchyts.marten.item-drag-payload")
}
