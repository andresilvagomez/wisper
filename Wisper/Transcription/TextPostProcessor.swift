import Foundation

enum TextPolishMode: String, CaseIterable {
    case off = "off"
    case basic = "basic"
    case fluent = "fluent"

    var localizedTitle: String {
        switch self {
        case .off:
            return L10n.t("text.polish.off")
        case .basic:
            return L10n.t("text.polish.basic")
        case .fluent:
            return L10n.t("text.polish.fluent")
        }
    }
}

enum TextPostProcessor {
    static func processChunk(_ text: String, mode: TextPolishMode, isFirstChunk: Bool) -> String {
        var value = normalizeWhitespace(in: text)

        switch mode {
        case .off:
            return value
        case .basic:
            if isFirstChunk {
                value = capitalizeInitialLetter(in: value)
            }
            return value
        case .fluent:
            value = removeFillerWords(in: value)
            value = normalizePunctuationSpacing(in: value)
            if isFirstChunk {
                value = capitalizeInitialLetter(in: value)
            }
            return value
        }
    }

    static func processFinal(_ text: String, mode: TextPolishMode) -> String {
        var value = normalizeWhitespace(in: text)
        guard !value.isEmpty else { return value }

        switch mode {
        case .off:
            return value
        case .basic:
            value = capitalizeSentenceStarts(in: value)
            value = normalizePunctuationSpacing(in: value)
            value = ensureTerminalPunctuation(in: value)
            return value
        case .fluent:
            value = removeFillerWords(in: value)
            value = normalizeWhitespace(in: value)
            value = capitalizeSentenceStarts(in: value)
            value = normalizePunctuationSpacing(in: value)
            value = ensureTerminalPunctuation(in: value)
            return value
        }
    }

    private static func normalizeWhitespace(in text: String) -> String {
        let squashed = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return squashed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeFillerWords(in text: String) -> String {
        let pattern = #"\b(uh+|um+|eh+|emm+|mmm+)\b"#
        let stripped = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return normalizeWhitespace(in: stripped)
    }

    private static func normalizePunctuationSpacing(in text: String) -> String {
        var value = text.replacingOccurrences(
            of: #"\s+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"([,.;:!?])([^\s\d])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return normalizeWhitespace(in: value)
    }

    private static func capitalizeInitialLetter(in text: String) -> String {
        guard let idx = text.firstIndex(where: { $0.isLetter }) else { return text }
        var chars = Array(text)
        let offset = text.distance(from: text.startIndex, to: idx)
        chars[offset] = Character(String(chars[offset]).uppercased())
        return String(chars)
    }

    private static func capitalizeSentenceStarts(in text: String) -> String {
        var chars = Array(text)
        var shouldCapitalize = true

        for i in chars.indices {
            if shouldCapitalize, chars[i].isLetter {
                chars[i] = Character(String(chars[i]).uppercased())
                shouldCapitalize = false
                continue
            }

            if ".!?".contains(chars[i]) {
                shouldCapitalize = true
            }
        }

        return String(chars)
    }

    private static func ensureTerminalPunctuation(in text: String) -> String {
        guard let last = text.last else { return text }
        if ".!?…".contains(last) { return text }
        return text + "."
    }
}
