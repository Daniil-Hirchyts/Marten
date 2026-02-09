import CoreData
import Foundation

public struct AssetCleanupPlan: Sendable {
    public struct Target: Hashable, Sendable {
        public let assetRef: UUID
        public let fileExtension: String?

        public init(assetRef: UUID, fileExtension: String?) {
            self.assetRef = assetRef
            self.fileExtension = fileExtension
        }
    }

    public let targets: [Target]
    public let filePaths: [String]

    public init(targets: [Target], filePaths: [String]) {
        self.targets = targets
        self.filePaths = filePaths
    }
}

public protocol AssetManagementServicing: Sendable {
    func updateThumbnail(objectID: NSManagedObjectID, data: Data, fileExtension: String) throws
    func updateLinkPreview(objectID: NSManagedObjectID, payload: LinkPreviewPayload) throws
    func updateImageData(objectID: NSManagedObjectID, imageData: Data) throws
    func markLinkPreviewFetchFailed(objectID: NSManagedObjectID, url: URL, fetchedAt: Date) throws

    func fetchPendingLinkPreviewTargets(limit: Int) throws
        -> [(objectID: NSManagedObjectID, url: URL)]

    func makeAssetCleanupPlan(for item: ClipItem) -> AssetCleanupPlan
    func executeAssetCleanupPlan(_ plan: AssetCleanupPlan)
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
