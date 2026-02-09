import CoreGraphics
import MartenMacServices
import XCTest

@testable import MartenMac

@MainActor
final class OCRCaptureCoordinatorTests: XCTestCase {
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
        var lastMode: OCRCaptureMode?
        var lastSnapshots: [CGDirectDisplayID: CGImage] = [:]
        var nextResult: OCRSelectionOverlayController.Result = .cancelled

        func beginSelection(
            mode: OCRCaptureMode,
            staticSnapshots: [CGDirectDisplayID: CGImage],
            completion: @escaping (OCRSelectionOverlayController.Result) -> Void
        ) {
            didStartSelection = true
            lastMode = mode
            lastSnapshots = staticSnapshots
            completion(nextResult)
        }

        func cancelSelection() {}
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
        private(set) var callCount = 0

        func recognizeText(in image: CGImage, preferredLanguageCode: String?) throws
            -> OCRRecognitionResult
        {
            callCount += 1
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
        private(set) var successCount = 0
        private(set) var failures: [String] = []

        func showSuccess() {
            successCount += 1
        }

        func showFailure(message: String) {
            failures.append(message)
        }
    }

    func testPermissionDeniedShowsGuidance() {
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
    }

    func testStaticModeUsesSnapshotFlow() {
        let selectionPresenter = TestSelectionPresenter()
        let displayID: CGDirectDisplayID = 77
        let selection = OCRSelection(
            displayID: displayID,
            rectInDisplayPoints: CGRect(x: 10, y: 10, width: 20, height: 12),
            displaySizeInPoints: CGSize(width: 100, height: 50),
            backingScaleFactor: 2
        )
        selectionPresenter.nextResult = .selected(selection)

        let recognizer = TestTextRecognizer()
        recognizer.result = OCRRecognitionResult(text: "Captured text", averageConfidence: 0.9, candidateCount: 1)

        let screenCapturer = TestScreenImageCapturer()
        let snapshot = makeImage(width: 200, height: 100)
        screenCapturer.displayImage = snapshot

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
            ocrSettings: TestOCRSettings(defaultCaptureMode: .staticSnapshot, preferredLanguageCode: nil, showCaptureNotification: true),
            staticSnapshotProvider: { [displayID: snapshot] },
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(selectionPresenter.lastMode, .staticSnapshot)
        XCTAssertEqual(selectionPresenter.lastSnapshots.keys.first, displayID)
        XCTAssertEqual(recognizer.callCount, 1)
        XCTAssertEqual(historyStore.storedTexts, ["Captured text"])
        XCTAssertEqual(resultIndicator.successCount, 1)
        XCTAssertTrue(
            pasteEngine.actions.contains {
                if case .copyPlainText(text: "Captured text") = $0 { return true }
                return false
            }
        )
    }

    func testLiveModeCapturesLiveRegion() {
        let selectionPresenter = TestSelectionPresenter()
        selectionPresenter.nextResult = .selected(
            OCRSelection(
                displayID: 11,
                rectInDisplayPoints: CGRect(x: 2, y: 2, width: 12, height: 8),
                displaySizeInPoints: CGSize(width: 100, height: 50),
                backingScaleFactor: 2
            )
        )

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
            ocrSettings: TestOCRSettings(defaultCaptureMode: .liveScreen, preferredLanguageCode: nil, showCaptureNotification: true),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(screenCapturer.captureRegionCalls, 1)
        XCTAssertEqual(historyStore.storedTexts, ["Live"])
        XCTAssertEqual(resultIndicator.successCount, 1)
        XCTAssertTrue(
            pasteEngine.actions.contains {
                if case .copyPlainText(text: "Live") = $0 { return true }
                return false
            }
        )
    }

    func testNoTextDoesNotOverwriteMarten() {
        var noTextFeedbackCount = 0
        let selectionPresenter = TestSelectionPresenter()
        selectionPresenter.nextResult = .selected(
            OCRSelection(
                displayID: 3,
                rectInDisplayPoints: CGRect(x: 0, y: 0, width: 20, height: 20),
                displaySizeInPoints: CGSize(width: 100, height: 100),
                backingScaleFactor: 2
            )
        )

        let recognizer = TestTextRecognizer()
        recognizer.result = OCRRecognitionResult(text: "   \n", averageConfidence: 0.1, candidateCount: 0)

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
            ocrSettings: TestOCRSettings(defaultCaptureMode: .liveScreen, preferredLanguageCode: nil, showCaptureNotification: true),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {
                noTextFeedbackCount += 1
            }
        )

        coordinator.startCapture()
        spinRunLoop(for: 0.2)

        XCTAssertEqual(noTextFeedbackCount, 1)
        XCTAssertTrue(historyStore.storedTexts.isEmpty)
        XCTAssertEqual(resultIndicator.failures.last, "No Text Found")
        XCTAssertFalse(
            pasteEngine.actions.contains {
                if case .copyPlainText = $0 { return true }
                return false
            }
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
            ocrSettings: TestOCRSettings(defaultCaptureMode: .staticSnapshot, preferredLanguageCode: nil, showCaptureNotification: true),
            processingQueue: DispatchQueue.main,
            noTextFeedback: {}
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
