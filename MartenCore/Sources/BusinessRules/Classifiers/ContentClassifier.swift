import Foundation

public protocol ContentClassifier {
    func classify(_ text: String) -> ClassificationResult
}

public enum ClassificationResult: Equatable {
    case safe
    case sensitive(SensitiveReason)
}

public enum SensitiveReason: String, CaseIterable {
    case password
    case oneTimeCode
    case creditCard
    case apiKey
    case privateKey
    case ssn
}

