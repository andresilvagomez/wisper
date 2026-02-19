import Testing
@testable import Wisper

@Suite("Language Support")
@MainActor
struct LanguageSupportTests {

    @Test("Catalog includes 100+ language options")
    func hasHundredPlusLanguages() {
        #expect(AppState.availableLanguages.count >= 101)
    }

    @Test("Catalog includes key multilingual entries")
    func includesKeyLanguages() {
        let codes = Set(AppState.availableLanguages.map(\.code))
        #expect(codes.contains("auto"))
        #expect(codes.contains("es"))
        #expect(codes.contains("en"))
        #expect(codes.contains("zh"))
        #expect(codes.contains("ar"))
        #expect(codes.contains("hi"))
        #expect(codes.contains("yue"))
    }

    @Test("Variant language codes normalize to whisper base code")
    func variantNormalization() {
        #expect(AppState.normalizeWhisperLanguageCode("pt-BR") == "pt")
        #expect(AppState.normalizeWhisperLanguageCode("en-US") == "en")
        #expect(AppState.normalizeWhisperLanguageCode("zh-Hant") == "zh")
        #expect(AppState.normalizeWhisperLanguageCode("az-Cyrl") == "az")
    }
}
