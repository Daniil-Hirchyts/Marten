import AppKit
@preconcurrency import MartenCore
@preconcurrency import MartenMacServices
import Combine
import CoreData
import Foundation
import OSLog

@MainActor
final class CaptureCoordinator {
    private let pasteboardMonitor: PasteboardMonitor
    private let pasteboardExtractor: PasteboardExtractor
    private let clipItemStore: ClipItemStore
    private let thumbnailGenerator: ThumbnailGenerator
    private let eventBroadcaster: any MartenEventBroadcaster
    private let captureQueue: DispatchQueue
    private let soundPlayer: SoundEffectPlayer
    private let linkPreviewFetcher: LinkPreviewFetcher
    private let linkPreviewSettings: any LinkPreviewSettingsProviding

    private var cancellables: Set<AnyCancellable> = []
    private var lastCapturedHash: String?

    init(
        pasteboardMonitor: PasteboardMonitor,
        pasteboardExtractor: PasteboardExtractor,
        clipItemStore: ClipItemStore,
        thumbnailGenerator: ThumbnailGenerator,
        eventBroadcaster: any MartenEventBroadcaster,
        captureQueue: DispatchQueue,
        soundPlayer: SoundEffectPlayer,
        linkPreviewFetcher: LinkPreviewFetcher,
        linkPreviewSettings: any LinkPreviewSettingsProviding
    ) {
        self.pasteboardMonitor = pasteboardMonitor
        self.pasteboardExtractor = pasteboardExtractor
        self.clipItemStore = clipItemStore
        self.thumbnailGenerator = thumbnailGenerator
        self.eventBroadcaster = eventBroadcaster
        self.captureQueue = captureQueue
        self.soundPlayer = soundPlayer
        self.linkPreviewFetcher = linkPreviewFetcher
        self.linkPreviewSettings = linkPreviewSettings
    }

    func start() {
        // No receive(on:) — suppression must run synchronously before the pasteboard
        // write that follows the publish.  All clipboardWillWrite publishes happen on the
        // main actor, so the PassthroughSubject delivers the sink on the main thread already.
        eventBroadcaster.events
            .sink { [weak self] event in
                guard let self else { return }
                guard event == .clipboardWillWrite else { return }
                // Pause momentarily to ignore our own write (which involves clear + set, potentially multiple change counts)
                self.pasteboardMonitor.pauseForDuration(1.0)
            }
            .store(in: &cancellables)

        pasteboardMonitor.onMartenChange = { [weak self] pasteboard in
            Task { @MainActor in
                self?.handlePasteboardChange(pasteboard)
            }
        }

        pasteboardMonitor.start()
    }

    func stop() {
        pasteboardMonitor.stop()
        cancellables.removeAll()
    }

    func schedulePendingLinkPreviewFetchesIfEnabled(limit: Int = 25) {
        guard linkPreviewSettings.isLinkPreviewEnabled else {
            return
        }

        let clipItemStore = clipItemStore
        captureQueue.async { [linkPreviewFetcher] in
            guard let pending = try? clipItemStore.fetchPendingLinkPreviewTargets(limit: limit)
            else {
                return
            }
            for target in pending {
                Self.scheduleLinkPreviewFetch(
                    itemID: target.objectID,
                    url: target.url,
                    clipItemStore: clipItemStore,
                    linkPreviewFetcher: linkPreviewFetcher
                )
            }
        }
    }

    private func handlePasteboardChange(_ pasteboard: NSPasteboard) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = SourceAppInfo(
            bundleID: frontmost?.bundleIdentifier,
            name: frontmost?.localizedName
        )
        let linkPreviewEnabled = linkPreviewSettings.isLinkPreviewEnabled

        guard let payload = pasteboardExtractor.extract(from: pasteboard) else {
            return
        }

        let payloadHash = Self.computePayloadHash(payload)

        let clipItemStore = clipItemStore
        let thumbnailGenerator = thumbnailGenerator
        captureQueue.async { [weak self] in
            do {
                let item = try clipItemStore.createItem(payload: payload, sourceApp: source)
                let itemID = item.objectID
                if let thumbnailData = Self.thumbnailData(
                    from: payload, thumbnailGenerator: thumbnailGenerator)
                {
                    try? clipItemStore.updateThumbnail(objectID: itemID, data: thumbnailData)
                }

                DispatchQueue.main.async { [weak self] in
                    self?.lastCapturedHash = payloadHash
                    self?.soundPlayer.play(.copy)
                }

                if linkPreviewEnabled, payload.needsLinkPreview, let text = payload.primaryText,
                    let url = URL(string: text)
                {
                    Self.scheduleLinkPreviewFetch(
                        itemID: itemID,
                        url: url,
                        clipItemStore: clipItemStore,
                        linkPreviewFetcher: self?.linkPreviewFetcher
                    )
                }

                Logger.pasteboard.info("Captured clipboard item")
            } catch {
                Logger.pasteboard.error(
                    "Failed to capture clipboard item: \(error.localizedDescription)")
                CrashReporter.shared.recordCaptureError(
                    error,
                    operation: "Create Item",
                    bundleID: source.bundleID
                )
            }
        }
    }

    nonisolated private static func thumbnailData(
        from payload: ClipItemPayload,
        thumbnailGenerator: ThumbnailGenerator
    ) -> Data? {
        let imageKinds: Set<RepresentationKind> = [.png, .jpeg, .tiff, .pdf]
        guard let imageRep = payload.representations.first(where: { imageKinds.contains($0.kind) }),
            let data = imageRep.data
        else {
            return nil
        }
        return try? thumbnailGenerator.generateThumbnail(from: data).get()
    }

    /// Mirrors the hash logic in ClipItemDeduplicationService so that CaptureCoordinator
    /// can detect duplicate content without a round-trip into Core Data.
    nonisolated private static func computePayloadHash(_ payload: ClipItemPayload) -> String {
        if let text = payload.primaryText, !text.isEmpty {
            return Data(text.utf8).sha256Hex()
        }
        for rep in payload.representations.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            if let text = rep.text, !text.isEmpty {
                return Data(text.utf8).sha256Hex()
            }
            if let data = rep.data, !data.isEmpty {
                return data.sha256Hex()
            }
        }
        return ""
    }

    private nonisolated static let maxConcurrentLinkPreviews = 3
    private nonisolated static let linkPreviewLock = NSLock()
    nonisolated(unsafe) private static var activeLinkPreviewCount = 0

    private nonisolated static func tryAcquireLinkPreviewSlot() -> Bool {
        linkPreviewLock.lock()
        defer { linkPreviewLock.unlock() }
        guard activeLinkPreviewCount < maxConcurrentLinkPreviews else { return false }
        activeLinkPreviewCount += 1
        return true
    }

    private nonisolated static func releaseLinkPreviewSlot() {
        linkPreviewLock.lock()
        activeLinkPreviewCount -= 1
        linkPreviewLock.unlock()
    }

    nonisolated private static func scheduleLinkPreviewFetch(
        itemID: NSManagedObjectID,
        url: URL,
        clipItemStore: ClipItemStore,
        linkPreviewFetcher: LinkPreviewFetcher?
    ) {
        guard let linkPreviewFetcher else {
            return
        }
        guard tryAcquireLinkPreviewSlot() else {
            return
        }

        Task.detached(priority: .utility) {
            defer { Self.releaseLinkPreviewSlot() }
            do {
                let preview = try await linkPreviewFetcher.fetchPreview(for: url)
                try clipItemStore.updateLinkPreview(objectID: itemID, payload: preview)
            } catch LinkPreviewError.disabled {
            } catch {
                try? clipItemStore.markLinkPreviewFetchFailed(objectID: itemID, url: url)
            }
        }
    }
}
