import SwiftUI

struct CodeSyntaxHighlighter {
    enum TokenKind: String {
        case keyword
        case string
        case number
        case comment
        case punctuation
        case plain
    }

    struct Token: Equatable {
        let text: String
        let kind: TokenKind
    }

    private static let keywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "do", "else", "enum", "extension", "false", "for", "func", "guard", "if",
        "import", "in", "init", "let", "nil", "private", "protocol", "public", "return",
        "self", "static", "struct", "switch", "throw", "throws", "true", "try", "var", "where",
        "while",
    ]

    private static let punctuation: Set<Character> = [
        "{", "}", "(", ")", "[", "]", ".", ",", ":", ";", "!", "?", "<", ">", "+", "-", "=",
        "*", "/", "&", "|", "@",
    ]

    static func tokenize(_ source: String) -> [Token] {
        let chars = Array(source)
        var tokens: [Token] = []
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
                var end = index + 2
                while end < chars.count && chars[end] != "\n" {
                    end += 1
                }
                tokens.append(Token(text: String(chars[index..<end]), kind: .comment))
                index = end
                continue
            }

            if char == "\"" || char == "'" {
                let quote = char
                var end = index + 1
                var escaped = false
                while end < chars.count {
                    let current = chars[end]
                    if current == "\\" && !escaped {
                        escaped = true
                        end += 1
                        continue
                    }
                    if current == quote && !escaped {
                        end += 1
                        break
                    }
                    escaped = false
                    end += 1
                }
                tokens.append(Token(text: String(chars[index..<min(end, chars.count)]), kind: .string))
                index = min(end, chars.count)
                continue
            }

            if char.isNumber {
                var end = index + 1
                while end < chars.count && (chars[end].isNumber || chars[end] == ".") {
                    end += 1
                }
                tokens.append(Token(text: String(chars[index..<end]), kind: .number))
                index = end
                continue
            }

            if char.isLetter || char == "_" {
                var end = index + 1
                while end < chars.count && (chars[end].isLetter || chars[end].isNumber || chars[end] == "_")
                {
                    end += 1
                }
                let word = String(chars[index..<end])
                let kind: TokenKind = keywords.contains(word) ? .keyword : .plain
                tokens.append(Token(text: word, kind: kind))
                index = end
                continue
            }

            if punctuation.contains(char) {
                tokens.append(Token(text: String(char), kind: .punctuation))
                index += 1
                continue
            }

            tokens.append(Token(text: String(char), kind: .plain))
            index += 1
        }

        return tokens
    }

    static func highlighted(_ source: String) -> AttributedString {
        var combined = AttributedString()

        for token in tokenize(source) {
            var attributed = AttributedString(token.text)
            attributed.foregroundColor = color(for: token.kind)
            combined += attributed
        }

        return combined
    }

    private static func color(for kind: TokenKind) -> Color {
        switch kind {
        case .keyword:
            return .blue
        case .string:
            return .orange
        case .number:
            return .mint
        case .comment:
            return .secondary
        case .punctuation:
            return .purple
        case .plain:
            return .primary
        }
    }
}
