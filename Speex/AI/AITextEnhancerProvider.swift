import Foundation

/// Contract for AI-powered text enhancement services.
///
/// Implementations take raw transcription text and return a cleaned-up,
/// well-formatted version — removing filler words, fixing grammar,
/// and improving readability while preserving meaning.
///
/// Designed for easy provider swapping (OpenAI, Claude, local LLM, etc.).
protocol AITextEnhancerProvider: AnyObject, Sendable {
    /// Enhance raw transcription text using AI.
    /// - Parameters:
    ///   - text: The raw transcribed text to enhance.
    ///   - language: Optional BCP-47 language code (e.g. "es", "en") to guide output language.
    /// - Returns: The enhanced, cleaned-up text.
    func enhance(text: String, language: String?) async throws -> String
}

enum AITextEnhancerError: LocalizedError, Sendable {
    case noAPIKey
    case emptyInput
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return L10n.t("cloud.error.no_api_key")
        case .emptyInput:
            return "Empty input text"
        case .invalidResponse:
            return "Invalid API response"
        case .apiError(let message):
            return message
        }
    }
}
