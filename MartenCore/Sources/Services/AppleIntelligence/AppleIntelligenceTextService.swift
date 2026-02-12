import Foundation
import FoundationModels

public actor AppleIntelligenceTextService: AppleIntelligenceTextTransforming {
    typealias AvailabilityResolver = @Sendable (Locale) -> AppleIntelligenceAvailability
    typealias Transformer = @Sendable (String, AppleIntelligenceTextAction, Locale) async throws ->
        String

    private let availabilityResolver: AvailabilityResolver
    private let transformer: Transformer

    public init(model: SystemLanguageModel = .default) {
        availabilityResolver = { locale in
            Self.availability(
                for: model.availability,
                localeSupported: model.supportsLocale(locale)
            )
        }

        transformer = { text, action, _ in
            let session = LanguageModelSession(model: model, instructions: Self.instructions(for: action))
            let response = try await session.respond(to: text)
            let transformed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transformed.isEmpty else {
                throw AppleIntelligenceTextTransformationError.emptyOutput
            }
            return transformed
        }
    }

    init(
        availabilityResolver: @escaping AvailabilityResolver,
        transformer: @escaping Transformer
    ) {
        self.availabilityResolver = availabilityResolver
        self.transformer = transformer
    }

    public func availability(for locale: Locale) async -> AppleIntelligenceAvailability {
        availabilityResolver(locale)
    }

    public func transform(_ text: String, action: AppleIntelligenceTextAction, locale: Locale)
        async throws -> String
    {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw AppleIntelligenceTextTransformationError.emptyInput
        }

        let availability = availabilityResolver(locale)
        if case .unavailable(let reason) = availability {
            throw AppleIntelligenceTextTransformationError.unavailable(reason)
        }

        do {
            return try await transformer(normalizedText, action, locale)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppleIntelligenceTextTransformationError {
            throw error
        } catch {
            throw AppleIntelligenceTextTransformationError.generationFailed
        }
    }
}

extension AppleIntelligenceTextService {
    static func availability(
        for modelAvailability: SystemLanguageModel.Availability,
        localeSupported: Bool
    ) -> AppleIntelligenceAvailability {
        switch modelAvailability {
        case .available:
            if !localeSupported {
                return .unavailable(.unsupportedLocale)
            }
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.modelNotReady)
            }
        }
    }

    static func instructions(for action: AppleIntelligenceTextAction) -> String {
        let commonInstruction =
            "Return only the rewritten text. Do not include commentary, explanations, markdown, quotes, or prefixes."

        switch action {
        case .summarize:
            return """
                Summarize the input in one to two sentences while preserving key meaning.
                \(commonInstruction)
                """
        case .proofread:
            return """
                Proofread and correct grammar, spelling, and punctuation while preserving tone and meaning.
                \(commonInstruction)
                """
        case .rewrite:
            return """
                Rewrite the input for clarity and flow while preserving the original meaning.
                \(commonInstruction)
                """
        case .shorten:
            return """
                Rewrite the input to be more concise while preserving key meaning.
                \(commonInstruction)
                """
        }
    }
}
