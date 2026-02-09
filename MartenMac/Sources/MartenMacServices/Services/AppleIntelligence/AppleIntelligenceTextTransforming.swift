import Foundation

public enum AppleIntelligenceTextAction: String, CaseIterable, Sendable {
    case summarize
    case proofread
    case rewrite
    case shorten

    public var title: String {
        switch self {
        case .summarize:
            "Summarize"
        case .proofread:
            "Proofread"
        case .rewrite:
            "Rewrite"
        case .shorten:
            "Shorten"
        }
    }
}

public enum AppleIntelligenceAvailability: Sendable, Equatable {
    case available
    case unavailable(UnavailableReason)

    public enum UnavailableReason: String, Sendable, Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unsupportedLocale
    }
}

public enum AppleIntelligenceTextTransformationError: Error, Sendable, Equatable {
    case unavailable(AppleIntelligenceAvailability.UnavailableReason)
    case emptyInput
    case emptyOutput
    case generationFailed
}

public protocol AppleIntelligenceTextTransforming: Sendable {
    func availability(for locale: Locale) async -> AppleIntelligenceAvailability
    func transform(_ text: String, action: AppleIntelligenceTextAction, locale: Locale) async throws
        -> String
}

public extension AppleIntelligenceTextTransforming {
    func availability() async -> AppleIntelligenceAvailability {
        await availability(for: .current)
    }

    func transform(_ text: String, action: AppleIntelligenceTextAction) async throws -> String {
        try await transform(text, action: action, locale: .current)
    }
}
