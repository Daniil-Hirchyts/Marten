import ClipboardCore

final class ClipboardContentFilter {
    struct Result {
        let shouldFilter: Bool
        let reason: String?
        let isSensitive: Bool
        let isTransient: Bool
    }

    private let settings: any CaptureSettingsProviding
    private let confidentialClassifier = ConfidentialContentClassifier()
    private let transientClassifier = TransientContentClassifier()

    init(settings: any CaptureSettingsProviding) {
        self.settings = settings
    }

    func evaluate(text: String?, types: [String], dataSize: Int) -> Result {
        let dedupedTypes = Array(Set(types))
        let normalizedSize = max(dataSize, 10)

        let isTransient = transientClassifier.isTransient(types: dedupedTypes, dataSize: normalizedSize)

        let confidentialResult: ClassificationResult? = text.map { confidentialClassifier.classify($0) }
        let isSensitive: Bool = {
            guard let confidentialResult else { return false }
            if case .sensitive = confidentialResult { return true }
            return false
        }()

        if settings.ignoreTransientContent, isTransient {
            return Result(shouldFilter: true, reason: "transient content", isSensitive: isSensitive, isTransient: isTransient)
        }

        if settings.ignoreConfidentialContent, let confidentialResult {
            if case .sensitive(let reason) = confidentialResult {
                return Result(
                    shouldFilter: true,
                    reason: "confidential: \(reason.rawValue)",
                    isSensitive: isSensitive,
                    isTransient: isTransient
                )
            }
        }

        return Result(shouldFilter: false, reason: nil, isSensitive: isSensitive, isTransient: isTransient)
    }
}
