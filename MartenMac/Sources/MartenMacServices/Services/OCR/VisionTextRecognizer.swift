import CoreGraphics
import Foundation
import OSLog
import Vision

public enum VisionTextRecognizerError: Error {
    case invalidRequestResult
}

public struct VisionTextRecognizer: TextRecognizing {
    public typealias RequestExecutor = (CGImage, OCRRecognitionPass) throws -> OCRRecognitionResult

    private let lowConfidenceThreshold: Float
    private let executor: RequestExecutor

    public init(
        lowConfidenceThreshold: Float = 0.35,
        executor: @escaping RequestExecutor = VisionTextRecognizer.executeRequest
    ) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.executor = executor
    }

    public func recognizeText(in image: CGImage, preferredLanguageCode: String?) throws
        -> OCRRecognitionResult
    {
        let startedAt = Date()
        let autoResult = try executor(image, .autoDetect)

        let preferredLanguage = preferredLanguageCode?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let shouldRetryWithPreferred = shouldRetry(
            autoResult: autoResult,
            preferredLanguage: preferredLanguage
        )

        if shouldRetryWithPreferred, let preferredLanguage {
            do {
                let preferredResult = try executor(image, .preferredLanguage(preferredLanguage))
                if !preferredResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Logger.ocr.info(
                        "OCR finished with preferred language fallback (ms=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public), candidates=\(preferredResult.candidateCount, privacy: .public), confidence=\(preferredResult.averageConfidence, privacy: .public))"
                    )
                    return preferredResult
                }
            } catch {
                Logger.ocr.warning(
                    "OCR preferred language retry failed (ms=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public))"
                )
            }
        }

        Logger.ocr.info(
            "OCR finished (ms=\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public), candidates=\(autoResult.candidateCount, privacy: .public), confidence=\(autoResult.averageConfidence, privacy: .public))"
        )
        return autoResult
    }

    private func shouldRetry(autoResult: OCRRecognitionResult, preferredLanguage: String?) -> Bool {
        guard let preferredLanguage, !preferredLanguage.isEmpty else {
            return false
        }

        let trimmed = autoResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || autoResult.averageConfidence < lowConfidenceThreshold
    }

    public static func executeRequest(
        image: CGImage,
        pass: OCRRecognitionPass
    ) throws -> OCRRecognitionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        switch pass {
        case .autoDetect:
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
        case .preferredLanguage(let languageCode):
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = false
            }
            request.recognitionLanguages = [languageCode]
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            throw VisionTextRecognizerError.invalidRequestResult
        }

        let sorted = observations.sorted { lhs, rhs in
            let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDelta > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var lines: [String] = []
        var confidenceSum: Float = 0
        var candidateCount = 0

        for observation in sorted {
            guard let candidate = observation.topCandidates(1).first else { continue }
            lines.append(candidate.string)
            confidenceSum += candidate.confidence
            candidateCount += 1
        }

        let averageConfidence = candidateCount > 0 ? (confidenceSum / Float(candidateCount)) : 0
        let text = lines.joined(separator: "\n")
        return OCRRecognitionResult(
            text: text,
            averageConfidence: averageConfidence,
            candidateCount: candidateCount
        )
    }
}
