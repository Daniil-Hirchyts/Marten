import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
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
    private let eventBroadcaster: any ClipboardEventBroadcaster
    private let captureQueue: DispatchQueue
    private let soundPlayer: SoundEffectPlayer
    private let linkPreviewFetcher: LinkPreviewFetcher

    private var cancellables: Set<AnyCancellable> = []

    init(
        pasteboardMonitor: PasteboardMonitor,
        pasteboardExtractor: PasteboardExtractor,
        clipItemStore: ClipItemStore,
        thumbnailGenerator: ThumbnailGenerator,
        eventBroadcaster: any ClipboardEventBroadcaster,
        captureQueue: DispatchQueue,
        soundPlayer: SoundEffectPlayer,
        linkPreviewFetcher: LinkPreviewFetcher
    ) {
        self.pasteboardMonitor = pasteboardMonitor
        self.pasteboardExtractor = pasteboardExtractor
        self.clipItemStore = clipItemStore
        self.thumbnailGenerator = thumbnailGenerator
        self.eventBroadcaster = eventBroadcaster
        self.captureQueue = captureQueue
        self.soundPlayer = soundPlayer
        self.linkPreviewFetcher = linkPreviewFetcher
    }

    func start() {
        eventBroadcaster.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                guard event == .clipboardWillWrite else { return }
                self.pasteboardMonitor.suppressNextChange()
            }
            .store(in: &cancellables)

        pasteboardMonitor.onClipboardChange = { [weak self] pasteboard in
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
        guard UserDefaults.standard.bool(forKey: "generateLinkPreviews") else {
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

        guard let payload = pasteboardExtractor.extract(from: pasteboard) else {
            return
        }

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
                    self?.soundPlayer.play(.capture)
                }

                if payload.needsLinkPreview, let text = payload.primaryText,
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

    nonisolated private static func scheduleLinkPreviewFetch(
        itemID: NSManagedObjectID,
        url: URL,
        clipItemStore: ClipItemStore,
        linkPreviewFetcher: LinkPreviewFetcher?
    ) {
        guard UserDefaults.standard.bool(forKey: "generateLinkPreviews") else {
            return
        }
        guard let linkPreviewFetcher else {
            return
        }

        Task.detached(priority: .utility) {
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
