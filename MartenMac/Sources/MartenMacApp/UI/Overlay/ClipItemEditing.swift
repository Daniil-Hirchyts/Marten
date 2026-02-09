import MartenCore
import CoreData
import Foundation

protocol ClipItemEditing {
    func updateTextItem(objectID: NSManagedObjectID, newText: String) throws -> ClipItem
    func updateRichTextItem(objectID: NSManagedObjectID, newText: String, rtfData: Data) throws
        -> ClipItem
    func updateImageData(objectID: NSManagedObjectID, imageData: Data) throws
    func renameItem(objectID: NSManagedObjectID, title: String?) throws
    func updateFileName(objectID: NSManagedObjectID, newFileName: String) throws
}

extension ClipItemStore: ClipItemEditing {}
