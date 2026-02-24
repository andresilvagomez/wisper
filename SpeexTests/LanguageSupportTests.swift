import Testing
@testable import Speex

@Suite("Language Support")
@MainActor
struct LanguageSupportTests {

    @Test("Catalog includes 100+ language options")
    func hasHundredPlusLanguages() {
        #expect(LanguageCatalog.availableLanguages.count >= 101)
    }

    @Test("Catalog includes key multilingual entries")
    func includesKeyLanguages() {
        let codes = Set(LanguageCatalog.availableLanguages.map(\.code))
        #expect(codes.contains("auto"))
        #expect(codes.contains("es"))
        #expect(codes.contains("en"))
        #expect(codes.contains("zh"))
        #expect(codes.contains("ar"))
        #expect(codes.contains("hi"))
        #expect(codes.contains("yue"))
    }

    @Test("Interface language catalog includes system and supported locales")
    func interfaceLanguageCatalog() {
        let codes = Set(LanguageCatalog.availableInterfaceLanguages.map(\.code))
        #expect(codes.contains("system"))
        #expect(codes.contains("es"))
        #expect(codes.contains("en"))
    }

    @Test("Variant language codes normalize to whisper base code")
    func variantNormalization() {
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("pt-BR") == "pt")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("en-US") == "en")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("zh-Hant") == "zh")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("az-Cyrl") == "az")
    }

    @Test("Unknown language codes pass through unchanged")
    func unknownCodePassthrough() {
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("es") == "es")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("fr") == "fr")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("ja") == "ja")
    }

    @Test("All language codes are unique")
    func allCodesUnique() {
        let codes = LanguageCatalog.availableLanguages.map(\.code)
        #expect(codes.count == Set(codes).count)
    }

    @Test("Interface language catalog has expected count")
    func interfaceLanguageCount() {
        // system + es, en, pt, fr, de = 6
        #expect(LanguageCatalog.availableInterfaceLanguages.count == 6)
    }

    @Test("Normalization is case insensitive")
    func normalizationCaseInsensitive() {
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("PT-BR") == "pt")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("EN-us") == "en")
        #expect(LanguageCatalog.normalizeWhisperLanguageCode("ZH-HANS") == "zh")
    }
}
