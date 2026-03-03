import CoreGraphics
import MartenMacServices
import XCTest

@testable import MartenMac

@MainActor
final class OCRCaptureCoordinatorTests: XCTestCase {
    private final class TestEventRecorder {
        private(set) var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }
    }

    private enum TestError: Error {
        case recognitionFailed
    }

    private final class TestPermissionChecker: OCRPermissionChecking {
        var isAllowed: Bool
        var didRequestSettings = false

        init(isAllowed: Bool) {
            self.isAllowed = isAllowed
        }

        func checkScreenRecording(prompt: Bool) -> Bool {
            isAllowed
        }

        func requestScreenRecordingSettings() {
            didRequestSettings = true
        }
    }

    private final class TestSelectionPresenter: OCRSelectionPresenting {
        var didStartSelection = false
        var beginSelectionCallCount = 0
        var showProcessingStateCallCount = 0
        var endSessionCallCount = 0
        var lastMode: OCRCaptureMode?
        var lastSnapshots: [CGDirectDisplayID: CGImage] = [:]
        var nextResult: OCRSelectionOverlayController.Result = .cancelled
        var completeImmediately = true

        private let eventRecorder: TestEventRecorder?
        private var completion: ((OCRSelectionOverlayController.Result) -> Void)?

        init(eventRecorder: TestEventRecorder? = nil) {
            self.eventRecorder = eventRecorder
        }

        func beginSelection(
            mode: OCRCaptureMode,
            staticSnapshots: [CGDirectDisplayID: CGImage],
            completion: @escaping (OCRSelectionOverlayController.Result) -> Void
        ) {
            didStartSelection = true
            beginSelectionCallCount += 1
            lastMode = mode
            lastSnapshots = staticSnapshots
            self.completion = completion
            eventRecorder?.record("beginSelection")

            if completeImmediately {
                deliverResult()
            }
        }

        func showProcessingState() {
            showProcessingStateCallCount += 1
            eventRecorder?.record("showProcessingState")
        }

        func endSession() {
            endSessionCallCount += 1
            eventRecorder?.record("endSession")
            completion = nil
        }

        func deliverResult(_ result: OCRSelectionOverlayController.Result? = nil) {
            if let result {
                nextResult = result
            }

            let callback = completion
            completion = nil
            callback?(nextResult)
        }
    }

    private final class TestPermissionGuide: OCRPermissionGuiding {
        var didShowGuidance = false

        func showScreenRecordingPermissionGuidance(openSettings: @escaping () -> Void) {
            didShowGuidance = true
        }
    }

    private final class TestTextRecognizer: TextRecognizing {
        var result = OCRRecognitionResult(text: "", averageConfidence: 0, candidateCount: 0)
        var error: Error?

        private let lock = NSLock()
        private var handlers: [(CGImage, String?) throws -> OCRRecognitionResult] = []
        private(set) var callCount = 0

        func enqueueHandler(
            _ handler: @escaping (CGImage, String?) throws -> OCRRecognitionResult
        ) {
            lock.lock()
            handlers.append(handler)
            lock.unlock()
        }

        func recognizeText(in image: CGImage, preferredLanguageCode: String?) throws
            -> OCRRecognitionResult
        {
            let handler: ((CGImage, String?) throws -> OCRRecognitionResult)?
            let error: Error?
            let result: OCRRecognitionResult

            lock.lock()
            callCount += 1
            if handlers.isEmpty {
                handler = nil
            } else {
                handler = handlers.removeFirst()
            }
            error = self.error
            result = self.result
            lock.unlock()

            if let handler {
                return try handler(image, preferredLanguageCode)
            }
            if let error {
                throw error
            }
            return result
        }
    }

    private final class TestScreenImageCapturer: ScreenImageCapturing {
        var displayImage: CGImage?
        var regionImage: CGImage?
        private(set) var captureDisplayCalls = 0
        private(set) var captureRegionCalls = 0

        func captureDisplay(displayID: CGDirectDisplayID) -> CGImage? {
            captureDisplayCalls += 1
            return displayImage
        }

        func captureRegion(
            displayID: CGDirectDisplayID,
            rectInDisplayPoints: CGRect,
            displaySizeInPoints: CGSize,
            scale: CGFloat
        ) -> CGImage? {
            captureRegionCalls += 1
            return regionImage
        }
    }

    private struct TestOCRSettings: OCRSettingsProviding {
        let defaultCaptureMode: OCRCaptureMode
        let preferredLanguageCode: String?
        let showCaptureNotification: Bool
    }

    private final class TestHistoryStore: @unchecked Sendable, OCRHistoryStoring {
        private(set) var storedTexts: [String] = []

        func storeRecognizedText(_ text: String) throws {
            storedTexts.append(text)
        }
    }

    private final class TestResultIndicator: OCRResultIndicating {
        private let eventRecorder: TestEventRecorder?
        private(set) var successCount = 0
        private(set) var failures: [String] = []

        init(eventRecorder: TestEventRecorder? = nil) {
            self.eventRecorder = eventRecorder
        }

        func showSuccess() {
            successCount += 1
            eventRecorder?.record("showSuccess")
        }

        func showFailure(message: String) {
            failures.append(message)
            eventRecorder?.record("showFailure:\(message)")
        }
    }

    func testPermissionDeniedShowsGuidanceWithoutStartingOrEndingSession() {
        let permissionChecker = TestPermissionChecker(isAllowed: false)
        let selectionPresenter = TestSelectionPresenter()
        let permissionGuide = TestPermissionGuide()

        let coordinator = makeCoordinator(
            permissionChecker: permissionChecker,
            selectionPresenter: selectionPresenter,
            permissionGuide: permissionGuide
        )

        coordinator.startCapture()

        XCTAssertTrue(permissionGuide.didShowGuidance)
        XCTAssertFalse(selectionPresenter.didStartSelection)
        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 0)
    }

    func testStaticModeEndsSelectionSessionBeforeSuccessIndicator() {
        let eventRecorder = TestEventRecorder()
        let selectionPresenter = TestSelectionPresenter(eventRecorder: eventRecorder)
        let displayID: CGDirectDisplayID = 77
        selectionPresenter.nextResult = .selected(makeSelection(displayID: displayID))

        let recognizer = TestTextRecognizer()
        recognizer.result = OCRRecognitionResult(
            text: "Captured text",
            averageConfidence: 0.9,
            candidateCount: 1
        )

        let snapshot = makeImage(width: 200, height: 100)
        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.displayImage = snapshot

        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator(eventRecorder: eventRecorder)

        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .staticSnapshot,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            staticSnapshotProvider: { [displayID: snapshot] },
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(selectionPresenter.lastMode, .staticSnapshot)
        XCTAssertEqual(selectionPresenter.lastSnapshots.keys.first, displayID)
        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 1)
        XCTAssertEqual(recognizer.callCount, 1)
        XCTAssertEqual(historyStore.storedTexts, ["Captured text"])
        XCTAssertEqual(resultIndicator.successCount, 1)
        XCTAssertEqual(
            eventRecorder.events,
            ["beginSelection", "endSession", "showSuccess"]
        )
        XCTAssertTrue(
            pasteEngine.actions.contains {
                if case .copyPlainText(text: "Captured text") = $0 { return true }
                return false
            }
        )
    }

    func testLiveModeCapturesLiveRegionAndEndsSession() {
        let selectionPresenter = TestSelectionPresenter()
        selectionPresenter.nextResult = .selected(makeSelection(displayID: 11))

        let recognizer = TestTextRecognizer()
        recognizer.result = OCRRecognitionResult(text: "Live", averageConfidence: 0.8, candidateCount: 1)

        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.regionImage = makeImage(width: 20, height: 20)

        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator()
        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .liveScreen,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(screenCapturer.captureRegionCalls, 1)
        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 1)
        XCTAssertEqual(historyStore.storedTexts, ["Live"])
        XCTAssertEqual(resultIndicator.successCount, 1)
        XCTAssertTrue(
            pasteEngine.actions.contains {
                if case .copyPlainText(text: "Live") = $0 { return true }
                return false
            }
        )
    }

    func testNoTextEndsSelectionSessionBeforeFailureIndicator() {
        var noTextFeedbackCount = 0
        let eventRecorder = TestEventRecorder()
        let selectionPresenter = TestSelectionPresenter(eventRecorder: eventRecorder)
        selectionPresenter.nextResult = .selected(makeSelection(displayID: 3))

        let recognizer = TestTextRecognizer()
        recognizer.result = OCRRecognitionResult(text: "   \n", averageConfidence: 0.1, candidateCount: 0)

        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.regionImage = makeImage(width: 20, height: 20)
        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator(eventRecorder: eventRecorder)

        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .liveScreen,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {
                noTextFeedbackCount += 1
            }
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(noTextFeedbackCount, 1)
        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 1)
        XCTAssertTrue(historyStore.storedTexts.isEmpty)
        XCTAssertEqual(resultIndicator.failures.last, "No Text Found")
        XCTAssertEqual(
            eventRecorder.events,
            ["beginSelection", "endSession", "showFailure:No Text Found"]
        )
        XCTAssertFalse(
            pasteEngine.actions.contains {
                if case .copyPlainText = $0 { return true }
                return false
            }
        )
    }

    func testRecognitionFailureEndsSelectionSessionBeforeFailureIndicator() {
        let eventRecorder = TestEventRecorder()
        let selectionPresenter = TestSelectionPresenter(eventRecorder: eventRecorder)
        selectionPresenter.nextResult = .selected(makeSelection(displayID: 12))

        let recognizer = TestTextRecognizer()
        recognizer.error = TestError.recognitionFailed

        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.regionImage = makeImage(width: 20, height: 20)

        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator(eventRecorder: eventRecorder)

        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .liveScreen,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 1)
        XCTAssertTrue(historyStore.storedTexts.isEmpty)
        XCTAssertEqual(resultIndicator.failures, ["Recognition Failed"])
        XCTAssertEqual(
            eventRecorder.events,
            ["beginSelection", "endSession", "showFailure:Recognition Failed"]
        )
        XCTAssertFalse(
            pasteEngine.actions.contains {
                if case .copyPlainText = $0 { return true }
                return false
            }
        )
    }

    func testStopDuringSelectionEndsSessionWithoutProcessing() {
        let selectionPresenter = TestSelectionPresenter()
        selectionPresenter.completeImmediately = false
        selectionPresenter.nextResult = .selected(makeSelection(displayID: 21))

        let recognizer = TestTextRecognizer()
        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.regionImage = makeImage(width: 20, height: 20)
        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator()

        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .liveScreen,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue(label: "ocr.test.selection.stop"),
            noTextFeedback: {}
        )

        coordinator.startCapture()
        coordinator.stop()
        selectionPresenter.deliverResult()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(selectionPresenter.beginSelectionCallCount, 1)
        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 1)
        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertTrue(historyStore.storedTexts.isEmpty)
        XCTAssertEqual(resultIndicator.successCount, 0)
        XCTAssertTrue(resultIndicator.failures.isEmpty)
        XCTAssertFalse(
            pasteEngine.actions.contains {
                if case .copyPlainText = $0 { return true }
                return false
            }
        )
    }

    func testStopDuringProcessingSuppressesLateSideEffects() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        let selectionPresenter = TestSelectionPresenter()
        selectionPresenter.nextResult = .selected(makeSelection(displayID: 31))

        let recognizer = TestTextRecognizer()
        recognizer.enqueueHandler { _, _ in
            started.signal()
            _ = release.wait(timeout: .now() + 2)
            return OCRRecognitionResult(text: "Late", averageConfidence: 0.9, candidateCount: 1)
        }

        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.regionImage = makeImage(width: 20, height: 20)
        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator()

        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .liveScreen,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue(label: "ocr.test.processing.stop"),
            noTextFeedback: {}
        )

        coordinator.startCapture()
        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)

        coordinator.stop()
        release.signal()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 1)
        XCTAssertTrue(historyStore.storedTexts.isEmpty)
        XCTAssertEqual(resultIndicator.successCount, 0)
        XCTAssertTrue(resultIndicator.failures.isEmpty)
        XCTAssertFalse(
            pasteEngine.actions.contains {
                if case .copyPlainText = $0 { return true }
                return false
            }
        )
    }

    func testStaleProcessingCompletionFromPreviousSessionIsIgnored() {
        let firstStarted = DispatchSemaphore(value: 0)
        let firstRelease = DispatchSemaphore(value: 0)

        let selectionPresenter = TestSelectionPresenter()
        selectionPresenter.nextResult = .selected(makeSelection(displayID: 41))

        let recognizer = TestTextRecognizer()
        recognizer.enqueueHandler { _, _ in
            firstStarted.signal()
            _ = firstRelease.wait(timeout: .now() + 2)
            return OCRRecognitionResult(text: "Stale", averageConfidence: 0.9, candidateCount: 1)
        }
        recognizer.enqueueHandler { _, _ in
            OCRRecognitionResult(text: "Fresh", averageConfidence: 0.95, candidateCount: 1)
        }

        let screenCapturer = TestScreenImageCapturer()
        screenCapturer.regionImage = makeImage(width: 20, height: 20)
        let pasteEngine = TestPasteEngine()
        let historyStore = TestHistoryStore()
        let resultIndicator = TestResultIndicator()

        let coordinator = OCRCaptureCoordinator(
            permissionChecker: TestPermissionChecker(isAllowed: true),
            selectionPresenter: selectionPresenter,
            permissionGuide: TestPermissionGuide(),
            textRecognizer: recognizer,
            screenImageCapturer: screenCapturer,
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: pasteEngine,
            historyStore: historyStore,
            resultIndicator: resultIndicator,
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .liveScreen,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue(
                label: "ocr.test.processing.concurrent",
                attributes: .concurrent
            ),
            noTextFeedback: {}
        )

        coordinator.startCapture()
        XCTAssertEqual(firstStarted.wait(timeout: .now() + 1), .success)

        coordinator.stop()
        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        firstRelease.signal()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(selectionPresenter.beginSelectionCallCount, 2)
        XCTAssertEqual(selectionPresenter.showProcessingStateCallCount, 0)
        XCTAssertEqual(selectionPresenter.endSessionCallCount, 2)
        XCTAssertEqual(historyStore.storedTexts, ["Fresh"])
        XCTAssertEqual(resultIndicator.successCount, 1)
        XCTAssertTrue(resultIndicator.failures.isEmpty)
        XCTAssertEqual(
            pasteEngine.actions.filter {
                if case .copyPlainText = $0 { return true }
                return false
            },
            [.copyPlainText(text: "Fresh")]
        )
    }

    private func makeCoordinator(
        permissionChecker: TestPermissionChecker,
        selectionPresenter: TestSelectionPresenter,
        permissionGuide: TestPermissionGuide
    ) -> OCRCaptureCoordinator {
        OCRCaptureCoordinator(
            permissionChecker: permissionChecker,
            selectionPresenter: selectionPresenter,
            permissionGuide: permissionGuide,
            textRecognizer: TestTextRecognizer(),
            screenImageCapturer: TestScreenImageCapturer(),
            selectionImageCropper: SelectionImageCropper(),
            pasteEngine: TestPasteEngine(),
            ocrSettings: TestOCRSettings(
                defaultCaptureMode: .staticSnapshot,
                preferredLanguageCode: nil,
                showCaptureNotification: true
            ),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
        )
    }

    private func makeSelection(displayID: CGDirectDisplayID) -> OCRSelection {
        OCRSelection(
            displayID: displayID,
            rectInDisplayPoints: CGRect(x: 10, y: 10, width: 20, height: 12),
            displaySizeInPoints: CGSize(width: 100, height: 50),
            backingScaleFactor: 2
        )
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
