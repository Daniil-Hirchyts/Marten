import CoreData
import Foundation

public enum DataWipeScope: Sendable, Equatable {
    case global
}

public struct DataWipeResult: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let stage: String
        public let message: String

        public init(stage: String, message: String) {
            self.stage = stage
            self.message = message
        }
    }

    public let scope: DataWipeScope
    public let sharedPinboardsAttempted: Int
    public let sharedPinboardsProcessed: Int
    public let failures: [Failure]

    public var isSuccess: Bool {
        failures.isEmpty
    }

    public var failureSummary: String? {
        guard failures.isEmpty == false else { return nil }
        return failures
            .map { "\($0.stage): \($0.message)" }
            .joined(separator: "\n")
    }

    public init(
        scope: DataWipeScope,
        sharedPinboardsAttempted: Int,
        sharedPinboardsProcessed: Int,
        failures: [Failure]
    ) {
        self.scope = scope
        self.sharedPinboardsAttempted = sharedPinboardsAttempted
        self.sharedPinboardsProcessed = sharedPinboardsProcessed
        self.failures = failures
    }
}

public final class DataWipeService {
    public typealias ShareTearDownAction = (NSManagedObjectID) async throws -> Void
    public typealias FlushAction = () async -> Void
    public typealias InboundConvergenceAction = () async throws -> Void

    private struct SharedPinboardReference {
        let objectID: NSManagedObjectID
        let isOwner: Bool
    }

    private let persistenceController: PersistenceController
    private let clipItemStore: ClipItemStore
    private let stopSharingAction: ShareTearDownAction?
    private let leaveShareAction: ShareTearDownAction?
    private let flushPrivateOutbound: FlushAction?
    private let flushSharedOutbound: FlushAction?
    private let inboundConvergenceAction: InboundConvergenceAction?

    public init(
        persistenceController: PersistenceController,
        clipItemStore: ClipItemStore,
        stopSharingAction: ShareTearDownAction? = nil,
        leaveShareAction: ShareTearDownAction? = nil,
        flushPrivateOutbound: FlushAction? = nil,
        flushSharedOutbound: FlushAction? = nil,
        inboundConvergenceAction: InboundConvergenceAction? = nil
    ) {
        self.persistenceController = persistenceController
        self.clipItemStore = clipItemStore
        self.stopSharingAction = stopSharingAction
        self.leaveShareAction = leaveShareAction
        self.flushPrivateOutbound = flushPrivateOutbound
        self.flushSharedOutbound = flushSharedOutbound
        self.inboundConvergenceAction = inboundConvergenceAction
    }

    public func wipeEverything(scope: DataWipeScope = .global) async -> DataWipeResult {
        var failures: [DataWipeResult.Failure] = []

        let sharedReferences: [SharedPinboardReference]
        do {
            sharedReferences = try loadSharedPinboards()
        } catch {
            failures.append(
                .init(stage: "discover-shared-pinboards", message: error.localizedDescription)
            )
            sharedReferences = []
        }

        var processedSharedPinboards = 0
        for reference in sharedReferences {
            do {
                if reference.isOwner {
                    guard let stopSharingAction else {
                        throw DataWipeServiceError.missingShareAction
                    }
                    try await stopSharingAction(reference.objectID)
                } else {
                    guard let leaveShareAction else {
                        throw DataWipeServiceError.missingShareAction
                    }
                    try await leaveShareAction(reference.objectID)
                }
                processedSharedPinboards += 1
            } catch {
                failures.append(
                    .init(
                        stage: reference.isOwner ? "stop-sharing" : "leave-share",
                        message: error.localizedDescription
                    )
                )
            }
        }

        do {
            try clipItemStore.deleteAllItems()
        } catch {
            failures.append(.init(stage: "delete-local-data", message: error.localizedDescription))
        }

        await flushPrivateOutbound?()
        await flushSharedOutbound?()

        if let inboundConvergenceAction {
            do {
                try await inboundConvergenceAction()
            } catch {
                failures.append(
                    .init(stage: "post-wipe-inbound-sync", message: error.localizedDescription)
                )
            }
        }

        return DataWipeResult(
            scope: scope,
            sharedPinboardsAttempted: sharedReferences.count,
            sharedPinboardsProcessed: processedSharedPinboards,
            failures: failures
        )
    }

    private func loadSharedPinboards() throws -> [SharedPinboardReference] {
        let context = persistenceController.newBackgroundContext()
        return try context.performAndWait {
            let request = Pinboard.fetchRequest()
            request.predicate = NSPredicate(format: "isSystemMarten == NO AND shareMetadata != nil")
            request.returnsObjectsAsFaults = false

            return try context.fetch(request).compactMap { pinboard in
                guard let metadata = pinboard.shareMetadata else { return nil }
                return SharedPinboardReference(
                    objectID: pinboard.objectID,
                    isOwner: metadata.isOwner
                )
            }
        }
    }
}

private enum DataWipeServiceError: LocalizedError {
    case missingShareAction

    var errorDescription: String? {
        switch self {
        case .missingShareAction:
            return "Sharing operation is unavailable."
        }
    }
}
