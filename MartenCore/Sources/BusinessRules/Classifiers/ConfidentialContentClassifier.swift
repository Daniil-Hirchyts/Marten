import Foundation

public struct ConfidentialContentClassifier: ContentClassifier {
    public init() {}

    public func classify(_ text: String) -> ClassificationResult {
        let candidate = normalizeCandidate(text)
        guard !candidate.isEmpty else {
            return .safe
        }

        if containsPrivateKeyMarker(candidate) {
            return .sensitive(.privateKey)
        }

        if isAPIKey(candidate) {
            return .sensitive(.apiKey)
        }

        if isCreditCardNumber(candidate) {
            return .sensitive(.creditCard)
        }

        if isSSN(candidate) {
            return .sensitive(.ssn)
        }

        if isOneTimeCode(candidate) {
            return .sensitive(.oneTimeCode)
        }

        if isStrongPassword(candidate) {
            return .sensitive(.password)
        }

        return .safe
    }

    public func calculateEntropy(_ text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else {
            return 0
        }

        var counts: [Unicode.Scalar: Int] = [:]
        counts.reserveCapacity(min(scalars.count, 128))

        for scalar in scalars {
            counts[scalar, default: 0] += 1
        }

        let length = Double(scalars.count)
        var entropy: Double = 0
        for count in counts.values {
            let p = Double(count) / length
            entropy -= p * log2(p)
        }
        return entropy
    }
}

private extension ConfidentialContentClassifier {
    func normalizeCandidate(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, trimmed.first == "`", trimmed.last == "`" {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    func isOneTimeCode(_ text: String) -> Bool {
        guard (6...8).contains(text.count) else {
            return false
        }
        return text.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    func isStrongPassword(_ text: String) -> Bool {
        guard (8...64).contains(text.count) else {
            return false
        }

        if text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return false
        }

        if isLikelyURL(text) {
            return false
        }

        if isLikelyEmail(text) {
            return false
        }

        var hasUpper = false
        var hasLower = false
        var hasDigit = false
        var hasSymbol = false

        for scalar in text.unicodeScalars {
            if CharacterSet.uppercaseLetters.contains(scalar) {
                hasUpper = true
            } else if CharacterSet.lowercaseLetters.contains(scalar) {
                hasLower = true
            } else if CharacterSet.decimalDigits.contains(scalar) {
                hasDigit = true
            } else {
                hasSymbol = true
            }
        }

        let typeCount = [hasUpper, hasLower, hasDigit, hasSymbol].filter { $0 }.count
        guard typeCount >= 3 else {
            return false
        }

        return calculateEntropy(text) > 3.5
    }

    func isLikelyURL(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else {
            return false
        }

        guard match.range.location == 0, match.range.length == range.length else {
            return false
        }

        guard let url = match.url else {
            return false
        }

        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    func isLikelyEmail(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else {
            return false
        }

        guard match.range.location == 0, match.range.length == range.length else {
            return false
        }

        return match.url?.scheme?.lowercased() == "mailto"
    }

    func isCreditCardNumber(_ text: String) -> Bool {
        guard (13...19).contains(text.count) else {
            return false
        }
        let digits = text.compactMap { $0.wholeNumberValue }
        guard digits.count == text.count else {
            return false
        }
        return passesLuhn(digits)
    }

    func passesLuhn(_ digits: [Int]) -> Bool {
        var sum = 0
        var shouldDouble = false
        for digit in digits.reversed() {
            var add = digit
            if shouldDouble {
                add *= 2
                if add > 9 {
                    add -= 9
                }
            }
            sum += add
            shouldDouble.toggle()
        }
        return sum % 10 == 0
    }

    func isAPIKey(_ text: String) -> Bool {
        if isJWT(text) {
            return true
        }

        if isGitHubToken(text) {
            return true
        }

        if isAWSAccessKeyID(text) {
            return true
        }

        if isLongAlphanumericToken(text) {
            return true
        }

        return false
    }

    func isJWT(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return false
        }

        func isBase64URL(_ segment: Substring) -> Bool {
            guard !segment.isEmpty else {
                return false
            }
            return segment.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
            }
        }

        return parts.allSatisfy(isBase64URL)
    }

    func isGitHubToken(_ text: String) -> Bool {
        let prefixes = ["ghp_", "gho_", "ghs_", "ghu_", "ghr_"]
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else {
            return false
        }

        let remainder = text.dropFirst(prefix.count)
        guard remainder.count >= 20 else {
            return false
        }

        return remainder.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    func isAWSAccessKeyID(_ text: String) -> Bool {
        guard text.hasPrefix("AKIA"), text.count == 20 else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            CharacterSet.uppercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }

    func isLongAlphanumericToken(_ text: String) -> Bool {
        guard text.count >= 40 else {
            return false
        }
        return text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    func containsPrivateKeyMarker(_ text: String) -> Bool {
        let markers = [
            "BEGIN RSA PRIVATE KEY",
            "BEGIN OPENSSH PRIVATE KEY",
            "BEGIN EC PRIVATE KEY",
            "BEGIN DSA PRIVATE KEY",
            "BEGIN PGP PRIVATE KEY"
        ]
        return markers.contains(where: { text.contains($0) })
    }

    func isSSN(_ text: String) -> Bool {
        if text.count == 11 {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                return false
            }
            guard parts[0].count == 3, parts[1].count == 2, parts[2].count == 4 else {
                return false
            }
            return text.unicodeScalars.allSatisfy { scalar in
                CharacterSet.decimalDigits.contains(scalar) || scalar == "-"
            }
        }

        if text.count == 9 {
            return text.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }

        return false
    }
}

