import AppKit
@preconcurrency import ClipboardCore
@preconcurrency import ClipboardMacServices
import Foundation
import OSLog

protocol OCRPermissionChecking: AnyObject {
    func checkScreenRecording(prompt: Bool) -> Bool
    func requestScreenRecordingSettings()
}

extension PermissionManager: OCRPermissionChecking {}

@MainActor
protocol OCRPermissionGuiding {
    func showScreenRecordingPermissionGuidance(openSettings: @escaping () -> Void)
}

@MainActor
struct DefaultOCRPermissionGuide: OCRPermissionGuiding {
    func showScreenRecordingPermissionGuidance(openSettings: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText =
            "Paste needs Screen Recording permission to capture text from the screen."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }
}

protocol OCRHistoryStoring: AnyObject, Sendable {
    func storeRecognizedText(_ text: String) throws
}

extension ClipItemStore: OCRHistoryStoring {
    func storeRecognizedText(_ text: String) throws {
        let payload = ClipItemPayload(
            representations: [ClipRepresentationPayload.plainText(text)],
            primaryText: text,
            itemType: .text
        )
        let sourceApp = SourceAppInfo(
            bundleID: Bundle.main.bundleIdentifier,
            name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        )
        _ = try createItem(payload: payload, sourceApp: sourceApp, isUserCreated: false)
    }
}

final class OCRNoopHistoryStore: OCRHistoryStoring {
    func storeRecognizedText(_ text: String) throws {}
}

@MainActor
final class OCRCaptureCoordinator {
    private let permissionChecker: any OCRPermissionChecking
    private let selectionPresenter: any OCRSelectionPresenting
    private let permissionGuide: any OCRPermissionGuiding
    private let textRecognizer: any TextRecognizing
    private let screenImageCapturer: any ScreenImageCapturing
    private let selectionImageCropper: SelectionImageCropper
    private let pasteEngine: any PasteEngineProtocol
    private let historyStore: any OCRHistoryStoring
    private let resultIndicator: any OCRResultIndicating
    private let ocrSettings: any OCRSettingsProviding
    private let processingQueue: DispatchQueue
    private let noTextFeedback: @MainActor () -> Void
    private let staticSnapshotProvider: (@MainActor () -> [CGDirectDisplayID: CGImage])?
    private let soundPlayer: SoundEffectPlayer?

    init(
        permissionChecker: any OCRPermissionChecking,
        selectionPresenter: (any OCRSelectionPresenting)? = nil,
        permissionGuide: (any OCRPermissionGuiding)? = nil,
        textRecognizer: any TextRecognizing,
        screenImageCapturer: any ScreenImageCapturing,
        selectionImageCropper: SelectionImageCropper,
        pasteEngine: any PasteEngineProtocol,
        historyStore: (any OCRHistoryStoring)? = nil,
        resultIndicator: (any OCRResultIndicating)? = nil,
        ocrSettings: any OCRSettingsProviding,
        staticSnapshotProvider: (@MainActor () -> [CGDirectDisplayID: CGImage])? = nil,
        processingQueue: DispatchQueue = DispatchQueue(
            label: "paste.app.ocr",
            qos: .userInitiated
        ),
        noTextFeedback: @escaping @MainActor () -> Void = { NSSound.beep() },
        soundPlayer: SoundEffectPlayer? = nil
    ) {
        self.permissionChecker = permissionChecker
        self.selectionPresenter = selectionPresenter ?? OCRSelectionOverlayController()
        self.permissionGuide = permissionGuide ?? DefaultOCRPermissionGuide()
        self.textRecognizer = textRecognizer
        self.screenImageCapturer = screenImageCapturer
        self.selectionImageCropper = selectionImageCropper
        self.pasteEngine = pasteEngine
        self.historyStore = historyStore ?? OCRNoopHistoryStore()
        self.resultIndicator = resultIndicator ?? OCRNoopResultIndicator()
        self.ocrSettings = ocrSettings
        self.staticSnapshotProvider = staticSnapshotProvider
        self.processingQueue = processingQueue
        self.noTextFeedback = noTextFeedback
        self.soundPlayer = soundPlayer
    }

    func startCapture(modeOverride: OCRCaptureMode? = nil) {
        guard permissionChecker.checkScreenRecording(prompt: false) else {
            permissionGuide.showScreenRecordingPermissionGuidance { [weak self] in
                self?.permissionChecker.requestScreenRecordingSettings()
            }
            return
        }

        let mode = modeOverride ?? ocrSettings.defaultCaptureMode
        let staticSnapshots = prepareStaticSnapshotsIfNeeded(mode: mode)

        guard mode != .staticSnapshot || !staticSnapshots.isEmpty else {
            Logger.ocr.error("OCR static capture failed to acquire display snapshots")
            noTextFeedback()
            resultIndicator.showFailure(message: "Capture Failed")
            return
        }

        var didHandleSelectionResult = false
        selectionPresenter.beginSelection(mode: mode, staticSnapshots: staticSnapshots) {
            [weak self] result in
            guard let self else { return }
            guard !didHandleSelectionResult else {
                Logger.ocr.warning("Ignoring duplicate OCR selection result")
                return
            }
            didHandleSelectionResult = true

            switch result {
            case .cancelled:
                Logger.ocr.debug("OCR selection cancelled")
            case .selected(let selection):
                self.processSelection(selection, mode: mode, staticSnapshots: staticSnapshots)
            }
        }
    }

    func stop() {
        selectionPresenter.cancelSelection()
    }

    private func prepareStaticSnapshotsIfNeeded(mode: OCRCaptureMode)
        -> [CGDirectDisplayID: CGImage]
    {
        guard mode == .staticSnapshot else { return [:] }

        if let staticSnapshotProvider {
            return staticSnapshotProvider()
        }

        var snapshots: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            guard
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID
            else { continue }
            if let image = screenImageCapturer.captureDisplay(displayID: displayID) {
                snapshots[displayID] = image
            }
        }
        return snapshots
    }

    private func processSelection(
        _ selection: OCRSelection,
        mode: OCRCaptureMode,
        staticSnapshots: [CGDirectDisplayID: CGImage]
    ) {
        let preferredLanguage = ocrSettings.preferredLanguageCode
        let textRecognizer = self.textRecognizer
        let screenImageCapturer = self.screenImageCapturer
        let selectionImageCropper = self.selectionImageCropper

        processingQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = Date()

            guard let image = Self.captureImage(
                for: selection,
                mode: mode,
                staticSnapshots: staticSnapshots,
                screenImageCapturer: screenImageCapturer,
                selectionImageCropper: selectionImageCropper
            ) else {
                Logger.ocr.error("OCR capture failed to produce image")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.noTextFeedback()
                    self.resultIndicator.showFailure(message: "Capture Failed")
                }
                return
            }

            do {
                let result = try textRecognizer.recognizeText(
                    in: image,
                    preferredLanguageCode: preferredLanguage
                )
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)

                Logger.ocr.info(
                    "OCR capture completed (mode=\(mode.rawValue, privacy: .public), ms=\(elapsedMS, privacy: .public), candidates=\(result.candidateCount, privacy: .public), confidence=\(result.averageConfidence, privacy: .public))"
                )

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if text.isEmpty {
                        self.noTextFeedback()
                        self.resultIndicator.showFailure(message: "No Text Found")
                        return
                    }

                    do {
                        try await self.saveRecognizedText(text)
                        if self.ocrSettings.showCaptureNotification {
                            self.resultIndicator.showSuccess()
                            self.soundPlayer?.play(.capture)
                        }
                    } catch {
                        Logger.ocr.error(
                            "OCR save failed: \(error.localizedDescription, privacy: .private)"
                        )
                        self.noTextFeedback()
                        self.resultIndicator.showFailure(message: "Save Failed")
                    }
                }
            } catch {
                Logger.ocr.error("OCR recognition failed: \(error.localizedDescription, privacy: .private)")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.noTextFeedback()
                    self.resultIndicator.showFailure(message: "Recognition Failed")
                }
            }
        }
    }

    nonisolated private static func captureImage(
        for selection: OCRSelection,
        mode: OCRCaptureMode,
        staticSnapshots: [CGDirectDisplayID: CGImage],
        screenImageCapturer: any ScreenImageCapturing,
        selectionImageCropper: SelectionImageCropper
    ) -> CGImage? {
        switch mode {
        case .staticSnapshot:
            guard let staticSnapshot = staticSnapshots[selection.displayID] else {
                return nil
            }
            return selectionImageCropper.crop(
                image: staticSnapshot,
                selectionInDisplayPoints: selection.rectInDisplayPoints,
                displaySizeInPoints: selection.displaySizeInPoints,
                scale: selection.backingScaleFactor
            )
        case .liveScreen:
            return screenImageCapturer.captureRegion(
                displayID: selection.displayID,
                rectInDisplayPoints: selection.rectInDisplayPoints,
                displaySizeInPoints: selection.displaySizeInPoints,
                scale: selection.backingScaleFactor
            )
        }
    }

    @MainActor
    private func saveRecognizedText(_ text: String) async throws {
        do {
            try historyStore.storeRecognizedText(text)
        } catch {
            Logger.ocr.warning(
                "OCR history save failed on first attempt, retrying: \(error.localizedDescription, privacy: .private)"
            )
            try await Task.sleep(nanoseconds: 40_000_000)
            try historyStore.storeRecognizedText(text)
        }

        try await pasteEngine.copyPlainTextToClipboard(text)
    }
}
