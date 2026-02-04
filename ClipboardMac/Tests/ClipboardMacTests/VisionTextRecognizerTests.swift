import CoreGraphics
import XCTest

@testable import ClipboardMacServices

final class VisionTextRecognizerTests: XCTestCase {
    func testUsesAutoPassWhenResultIsGood() throws {
        var passes: [OCRRecognitionPass] = []
        let recognizer = VisionTextRecognizer(lowConfidenceThreshold: 0.5) { _, pass in
            passes.append(pass)
            return OCRRecognitionResult(
                text: "Hello",
                averageConfidence: 0.9,
                candidateCount: 1
            )
        }

        let result = try recognizer.recognizeText(in: makeImage(), preferredLanguageCode: "uk-UA")

        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(passes, [.autoDetect])
    }

    func testRetriesWithPreferredLanguageWhenAutoResultIsLowConfidence() throws {
        var passes: [OCRRecognitionPass] = []
        let recognizer = VisionTextRecognizer(lowConfidenceThreshold: 0.8) { _, pass in
            passes.append(pass)
            switch pass {
            case .autoDetect:
                return OCRRecognitionResult(text: "Noisy", averageConfidence: 0.2, candidateCount: 1)
            case .preferredLanguage:
                return OCRRecognitionResult(
                    text: "Preferred",
                    averageConfidence: 0.95,
                    candidateCount: 1
                )
            }
        }

        let result = try recognizer.recognizeText(in: makeImage(), preferredLanguageCode: "uk-UA")

        XCTAssertEqual(result.text, "Preferred")
        XCTAssertEqual(passes, [.autoDetect, .preferredLanguage("uk-UA")])
    }

    func testFallsBackToAutoWhenPreferredPassThrows() throws {
        enum TestError: Error { case failed }

        var passes: [OCRRecognitionPass] = []
        let recognizer = VisionTextRecognizer(lowConfidenceThreshold: 0.8) { _, pass in
            passes.append(pass)
            switch pass {
            case .autoDetect:
                return OCRRecognitionResult(text: "Fallback", averageConfidence: 0.3, candidateCount: 1)
            case .preferredLanguage:
                throw TestError.failed
            }
        }

        let result = try recognizer.recognizeText(in: makeImage(), preferredLanguageCode: "en-US")

        XCTAssertEqual(result.text, "Fallback")
        XCTAssertEqual(passes, [.autoDetect, .preferredLanguage("en-US")])
    }

    private func makeImage(width: Int = 2, height: Int = 2) -> CGImage {
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
