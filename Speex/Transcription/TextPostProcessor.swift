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
    enum EditingCommand {
        case deleteLastSentence
        case undo
        case redo
    }

    static func separatorForPause(
        since lastChunkDate: Date?,
        previousText: String,
        now: Date = .now
    ) -> String {
        guard let lastChunkDate else { return "" }
        let gap = now.timeIntervalSince(lastChunkDate)
        let trimmed = previousText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastChar = trimmed.last else { return "" }
        guard !".,;:!?…".contains(lastChar) else { return " " }

        if gap >= 1.1 { return ". " }
        if gap >= 0.55 { return ", " }
        return " "
    }

    static func processChunk(_ text: String, mode: TextPolishMode, isFirstChunk: Bool) -> String {
        var value = normalizeWhitespacePreservingLineBreaks(in: text)
        value = applySpokenFormattingCommands(in: value)
        value = applyDictatedPunctuation(in: value)
        value = normalizePunctuationSpacing(in: value)

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

    static func editingCommand(in text: String) -> EditingCommand? {
        let normalized = normalizeWhitespace(in: text).lowercased()
        guard !normalized.isEmpty else { return nil }

        if matchesAny(normalized, patterns: [
            #"^(borra|elimina|quita)\s+(la\s+)?[uú]ltima\s+frase$"#,
            #"^delete\s+(the\s+)?last\s+sentence$"#,
            #"^apaga\s+(a\s+)?[uú]ltima\s+frase$"#,
            #"^supprime\s+(la\s+)?derni[eè]re\s+phrase$"#,
            #"^l[öo]sche\s+(den\s+)?letzten\s+satz$"#,
        ]) {
            return .deleteLastSentence
        }

        if matchesAny(normalized, patterns: [
            #"^deshacer$"#,
            #"^undo$"#,
            #"^desfazer$"#,
            #"^annuler$"#,
            #"^r[üu]ckg[aä]ngig$"#,
        ]) {
            return .undo
        }

        if matchesAny(normalized, patterns: [
            #"^(rehacer|repite)$"#,
            #"^(redo|repeat)$"#,
            #"^(refazer|repetir)$"#,
            #"^(r[eé]tablir|r[eé]p[eé]ter)$"#,
            #"^(wiederholen|wiederherstellen)$"#,
        ]) {
            return .redo
        }

        return nil
    }

    static func processFinal(_ text: String, mode: TextPolishMode) -> String {
        var value = normalizeWhitespacePreservingLineBreaks(in: text)
        value = applySpokenFormattingCommands(in: value)
        value = applyDictatedPunctuation(in: value)
        value = normalizePunctuationSpacing(in: value)
        guard !value.isEmpty else { return value }

        switch mode {
        case .off:
            return value
        case .basic:
            value = capitalizeSentenceStarts(in: value)
            if let numbered = formatNumberedListIfDetected(in: value) {
                return numbered
            }
            value = ensureTerminalPunctuation(in: value)
            return value
        case .fluent:
            value = removeFillerWords(in: value)
            value = normalizeWhitespacePreservingLineBreaks(in: value)
            value = capitalizeSentenceStarts(in: value)
            if let numbered = formatNumberedListIfDetected(in: value) {
                return numbered
            }
            value = ensureTerminalPunctuation(in: value)
            return value
        }
    }

    static func correctionReplacementIfCommand(_ text: String) -> String? {
        let normalized = normalizeWhitespace(in: text)
        guard !normalized.isEmpty else { return nil }

        let patterns: [String] = [
            #"^(?:no[\s,]+)?(?:quise decir|correcci[oó]n|corrijo)\s+(.+)$"#,
            #"^(?:no[\s,]+)?(?:i meant|correction)\s+(.+)$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsValue = normalized as NSString
            let range = NSRange(location: 0, length: nsValue.length)
            guard let match = regex.firstMatch(in: normalized, options: [], range: range),
                  match.numberOfRanges >= 2 else {
                continue
            }

            let replacement = nsValue.substring(with: match.range(at: 1))
            let polished = processFinal(replacement, mode: .fluent)
            if !polished.isEmpty {
                return polished
            }
        }

        return nil
    }

    static func replacingLastSentence(in text: String, with replacement: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementTrimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacementTrimmed.isEmpty else { return trimmed }
        guard !trimmed.isEmpty else { return replacementTrimmed }

        let punctuation = ".!?"
        let punctuationPositions = trimmed.indices.filter { punctuation.contains(trimmed[$0]) }

        if punctuationPositions.count >= 2 {
            let previousSentenceEnd = punctuationPositions[punctuationPositions.count - 2]
            let prefix = trimmed[...previousSentenceEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(prefix) \(replacementTrimmed)"
        }

        return replacementTrimmed
    }

    static func removingLastSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let punctuation = ".!?"
        let punctuationPositions = trimmed.indices.filter { punctuation.contains(trimmed[$0]) }

        guard !punctuationPositions.isEmpty else { return "" }
        guard punctuationPositions.count >= 2 else { return "" }

        let previousSentenceEnd = punctuationPositions[punctuationPositions.count - 2]
        return String(trimmed[...previousSentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(in text: String) -> String {
        let squashed = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return squashed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesAny(_ value: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(location: 0, length: (value as NSString).length)
            if regex.firstMatch(in: value, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    private static func normalizeWhitespacePreservingLineBreaks(in text: String) -> String {
        let lines = text
            .replacingOccurrences(of: #"\r\n?"#, with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { line in
                line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }

        let joined = lines.joined(separator: "\n")
        let squashedBreaks = joined.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return squashedBreaks.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applySpokenFormattingCommands(in text: String) -> String {
        var value = " \(text) "
        let replacements: [(pattern: String, replacement: String)] = [
            (#"\b(new line|nueva l[ií]nea|nova linha|nouvelle ligne|neue zeile)\b"#, "\n"),
            (#"\b(new paragraph|nuevo p[aá]rrafo|novo par[aá]grafo|nouveau paragraphe|neuer absatz)\b"#, "\n\n"),
        ]

        for item in replacements {
            value = value.replacingOccurrences(
                of: item.pattern,
                with: " \(item.replacement) ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizeWhitespacePreservingLineBreaks(in: value)
    }

    private static func applyDictatedPunctuation(in text: String) -> String {
        var value = " \(text) "
        let replacements: [(pattern: String, replacement: String)] = [
            (#"\b(question mark|signo de pregunta|ponto de interroga[cç][aã]o|point d['’]interrogation|fragezeichen)\b"#, "?"),
            (#"\b(exclamation mark|signo de exclamaci[oó]n|ponto de exclama[cç][aã]o|point d['’]exclamation|ausrufezeichen)\b"#, "!"),
            (#"\b(comma|coma|v[ií]rgula|virgule|komma)\b"#, ","),
            (#"\b(period|punto|ponto|point|punkt)\b"#, "."),
            (#"\b(colon|dos puntos|dois pontos|deux points|doppelpunkt)\b"#, ":"),
            (#"\b(semicolon|punto y coma|ponto e v[ií]rgula|point virgule|semikolon)\b"#, ";"),
        ]

        for item in replacements {
            value = value.replacingOccurrences(
                of: item.pattern,
                with: " \(item.replacement) ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizeWhitespacePreservingLineBreaks(in: value)
    }

    private static func removeFillerWords(in text: String) -> String {
        let pattern = #"\b(uh+|um+|eh+|emm+|mmm+|este+|ehm+)\b"#
        let stripped = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return normalizeWhitespacePreservingLineBreaks(in: stripped)
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
        return normalizeWhitespacePreservingLineBreaks(in: value)
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
            } else if chars[i] == "\n" {
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

    private static func formatNumberedListIfDetected(in text: String) -> String? {
        // Example detected pattern:
        // "Going to the store for 1. Apples 2. Bananas 3. Oranges."
        let pattern = #"(?s)(?:^|\s)(\d+)\.\s*([\s\S]*?)(?=(?:\s\d+\.\s)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        guard matches.count >= 2 else { return nil }

        var listItems: [(number: Int, text: String)] = []
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let numberString = nsText.substring(with: match.range(at: 1))
            guard let number = Int(numberString) else { continue }
            let itemRaw = nsText.substring(with: match.range(at: 2))
            let itemClean = cleanListItem(itemRaw)
            guard !itemClean.isEmpty else { continue }
            listItems.append((number: number, text: itemClean))
        }

        guard listItems.count >= 2 else { return nil }
        guard listItems.first?.number == 1 else { return nil }

        for idx in 1..<listItems.count where listItems[idx].number != listItems[idx - 1].number + 1 {
            return nil
        }

        return listItems
            .map { "\($0.number). \($0.text)" }
            .joined(separator: "\n")
    }

    private static func cleanListItem(_ raw: String) -> String {
        var item = normalizeWhitespace(in: raw)
        item = item.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-–— "))
        return capitalizeInitialLetter(in: item)
    }
}
