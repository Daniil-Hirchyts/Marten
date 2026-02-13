import CoreData
import Foundation
import MartenCore
import os.log

private let logger = Logger(subsystem: "com.hirchyts.marten", category: "LinkPreviewCoordinator")

protocol LinkPreviewFetching: Sendable {
    func fetchPreview(for url: URL) async throws -> LinkPreviewPayload
}

extension LinkPreviewFetcher: LinkPreviewFetching {}

protocol ClockProviding: Sendable {
    var now: Date { get }
}

struct SystemClock: ClockProviding {
    var now: Date { Date() }
}

public actor LinkPreviewCoordinator {
    private let store: ClipItemStore
    private let fetcher: any LinkPreviewFetching
    private let clock: any ClockProviding
    private let maxConcurrentFetches: Int

    /// Prevents overlapping fetch cycles from the multiple trigger points.
    private var isFetching = false

    public init(
        store: ClipItemStore,
        maxConcurrentFetches: Int = 3
    ) {
        self.init(
            store: store,
            fetcher: LinkPreviewFetcher(),
            clock: SystemClock(),
            maxConcurrentFetches: maxConcurrentFetches
        )
    }

    init(
        store: ClipItemStore,
        fetcher: any LinkPreviewFetching,
        clock: any ClockProviding = SystemClock(),
        maxConcurrentFetches: Int = 3
    ) {
        self.store = store
        self.fetcher = fetcher
        self.clock = clock
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
    }

    public func fetchPending(limit: Int = 25) async {
        guard !isFetching else {
            logger.debug("Skipping fetchPending — already in progress")
            return
        }

        isFetching = true
        defer { isFetching = false }

        let targets: [(objectID: NSManagedObjectID, url: URL)]
        do {
            targets = try store.fetchPendingLinkPreviewTargets(limit: limit)
        } catch {
            logger.error("Failed to fetch pending targets: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard !targets.isEmpty else { return }

        logger.info("Processing \(targets.count) pending link preview targets")
        let mapped = targets.map { PreviewTarget(objectID: $0.objectID, url: $0.url) }
        await processTargets(mapped)
    }

    public func fetchOne(objectID: NSManagedObjectID, url: URL) async {
        await processTargets([PreviewTarget(objectID: objectID, url: url)])
    }

    private func processTargets(_ targets: [PreviewTarget]) async {
        guard !targets.isEmpty else { return }

        var startIndex = 0
        while startIndex < targets.count {
            let endIndex = min(startIndex + maxConcurrentFetches, targets.count)
            let batch = Array(targets[startIndex..<endIndex])

            await withTaskGroup(of: Void.self) { group in
                for target in batch {
                    group.addTask { [store, fetcher, clock] in
                        do {
                            let preview = try await fetcher.fetchPreview(for: target.url)
                            try store.updateLinkPreview(objectID: target.objectID, payload: preview)
                            logger.info("Saved preview for \(target.url.absoluteString, privacy: .public)")
                        } catch LinkPreviewError.disabled {
                            return
                        } catch {
                            logger.warning("Failed preview for \(target.url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                            do {
                                try store.markLinkPreviewFetchFailed(
                                    objectID: target.objectID,
                                    url: target.url,
                                    fetchedAt: clock.now
                                )
                            } catch {
                                logger.error("Failed to mark fetch failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }
                }
            }

            startIndex = endIndex
        }
    }
}

private struct PreviewTarget: @unchecked Sendable {
    let objectID: NSManagedObjectID
    let url: URL
}
