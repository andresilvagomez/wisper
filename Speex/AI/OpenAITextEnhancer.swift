import Foundation

final class OpenAITextEnhancer: AITextEnhancerProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
        self.session = URLSession(configuration: .ephemeral)
    }

    func enhance(text: String, language: String?) async throws -> String {
        guard !apiKey.isEmpty else { throw AITextEnhancerError.noAPIKey }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AITextEnhancerError.emptyInput }

        let systemPrompt = Self.buildSystemPrompt(language: language)
        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: trimmed),
            ],
            temperature: 0.3
        )

        let jsonData = try JSONEncoder().encode(body)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AITextEnhancerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[Speex AI] API error \(httpResponse.statusCode): \(errorBody)")
            throw AITextEnhancerError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw AITextEnhancerError.invalidResponse
        }

        let enhanced = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !enhanced.isEmpty else { throw AITextEnhancerError.invalidResponse }

        print("[Speex AI] Enhanced \(trimmed.count) → \(enhanced.count) chars")
        return enhanced
    }

    // MARK: - System Prompt

    private static func buildSystemPrompt(language: String?) -> String {
        let langInstruction: String
        if let language, language != "auto" {
            langInstruction = "The text is in language code '\(language)'. Keep the output in the same language."
        } else {
            langInstruction = "Detect the language and keep the output in the same language."
        }

        return """
        You are a precise text editor for voice transcriptions. Apply these rules:

        FILLER REMOVAL
        Remove all filler words and verbal pauses: uh, um, like, you know, I mean, \
        so yeah, basically, este, ehm, mmm, pues, o sea, bueno (as filler), etc. \
        The output must read as if the speaker never hesitated.

        MIND CHANGES
        When the speaker corrects themselves mid-sentence, keep ONLY the corrected version. \
        Examples: "Let's meet at 2 actually 3" → "Let's meet at 3." \
        "Send it to Juan no wait to María" → "Send it to María." \
        "The budget is 500 I mean 5000 dollars" → "The budget is 5000 dollars."

        AUTO PUNCTUATION
        Add proper punctuation (periods, commas, question marks, exclamation marks) \
        based on sentence structure and natural pauses. Ensure every sentence ends with \
        appropriate punctuation. Capitalize after sentence boundaries.

        NUMBERED LISTS
        When the speaker enumerates items (first, second, third / uno, dos, tres / \
        number one, number two), format as a clean numbered list with line breaks:
        1. First item
        2. Second item

        GENERAL RULES
        - Fix grammar and spelling errors.
        - Make rambling sentences concise and clear.
        - Preserve the original meaning, tone, and intent exactly.
        - Keep proper nouns, technical terms, and numbers unchanged.
        - Maintain paragraph breaks if present.
        - Do NOT add information, opinions, or commentary.
        - Do NOT wrap the text in quotes or add prefixes.

        \(langInstruction)

        Return ONLY the cleaned text. Nothing else.
        """
    }
}

// MARK: - API Types

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: MessageContent
    }

    struct MessageContent: Decodable {
        let content: String
    }
}
