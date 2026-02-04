import CoreGraphics
import Foundation

public struct OCRRecognitionResult: Equatable, Sendable {
    public let text: String
    public let averageConfidence: Float
    public let candidateCount: Int

    public init(text: String, averageConfidence: Float, candidateCount: Int) {
        self.text = text
        self.averageConfidence = averageConfidence
        self.candidateCount = candidateCount
    }
}

public enum OCRRecognitionPass: Equatable, Sendable {
    case autoDetect
    case preferredLanguage(String)
}

public protocol TextRecognizing {
    func recognizeText(in image: CGImage, preferredLanguageCode: String?) throws
        -> OCRRecognitionResult
}
