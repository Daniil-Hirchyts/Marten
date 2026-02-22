import Foundation

enum RichTextFormattingTransforms {
    static func applyBulletList(to text: String, prefix: String = "• ") -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let stringLine = String(line)
                if stringLine.isEmpty || stringLine.hasPrefix(prefix) {
                    return stringLine
                }
                return prefix + stringLine
            }
            .joined(separator: "\n")
    }

    static func applyNumberedList(to text: String, startAt: Int = 1) -> String {
        var counter = max(1, startAt)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let stringLine = String(line)
                guard !stringLine.isEmpty else { return stringLine }
                defer { counter += 1 }
                return "\(counter). \(stringLine)"
            }
            .joined(separator: "\n")
    }
}
