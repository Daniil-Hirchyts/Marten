import CoreData
import Foundation

public protocol AssetManagementServicing: Sendable {
    func updateThumbnail(objectID: NSManagedObjectID, data: Data, fileExtension: String) throws
    func updateLinkPreview(objectID: NSManagedObjectID, payload: LinkPreviewPayload) throws
    func updateImageData(objectID: NSManagedObjectID, imageData: Data) throws
    func markLinkPreviewFetchFailed(objectID: NSManagedObjectID, url: URL, fetchedAt: Date) throws

    func fetchPendingLinkPreviewTargets(limit: Int) throws
        -> [(objectID: NSManagedObjectID, url: URL)]

    func removeAssets(for item: ClipItem)
}

public extension AssetManagementServicing {
    func updateThumbnail(objectID: NSManagedObjectID, data: Data) throws {
        try updateThumbnail(objectID: objectID, data: data, fileExtension: "png")
    }

    func markLinkPreviewFetchFailed(objectID: NSManagedObjectID, url: URL) throws {
        try markLinkPreviewFetchFailed(objectID: objectID, url: url, fetchedAt: Date())
    }

    func fetchPendingLinkPreviewTargets(limit: Int = 25) throws
        -> [(objectID: NSManagedObjectID, url: URL)]
    {
        try fetchPendingLinkPreviewTargets(limit: limit)
    }
}
