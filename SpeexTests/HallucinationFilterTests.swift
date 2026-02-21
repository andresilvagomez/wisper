import Testing
@testable import Speex

@Suite("Hallucination Filter")
struct HallucinationFilterTests {

    // MARK: - Known hallucinations should be filtered

    @Test("Filters [música] tag")
    func filtersMusica() {
        #expect(TranscriptionEngine.isHallucination("[música]"))
    }

    @Test("Filters [music] tag")
    func filtersMusic() {
        #expect(TranscriptionEngine.isHallucination("[music]"))
    }

    @Test("Filters [applause] tag")
    func filtersApplause() {
        #expect(TranscriptionEngine.isHallucination("[applause]"))
    }

    @Test("Filters [silence] tag")
    func filtersSilence() {
        #expect(TranscriptionEngine.isHallucination("[silence]"))
    }

    @Test("Filters parenthesized sound tags")
    func filtersParenthesized() {
        #expect(TranscriptionEngine.isHallucination("(música)"))
        #expect(TranscriptionEngine.isHallucination("(music)"))
    }

    @Test("Filters music symbols")
    func filtersMusicSymbols() {
        #expect(TranscriptionEngine.isHallucination("♪"))
        #expect(TranscriptionEngine.isHallucination("♫"))
    }

    @Test("Filters common Spanish hallucination phrases")
    func filtersSpanishHallucinations() {
        #expect(TranscriptionEngine.isHallucination("Gracias por ver"))
        #expect(TranscriptionEngine.isHallucination("subtítulos"))
    }

    @Test("Filters common English hallucination phrases")
    func filtersEnglishHallucinations() {
        #expect(TranscriptionEngine.isHallucination("thanks for watching"))
        #expect(TranscriptionEngine.isHallucination("subscribe"))
    }

    @Test("Removes leading thank-you artifact while preserving real content")
    func stripsLeadingThankYouArtifact() {
        let cleaned = TranscriptionEngine.sanitizedLeadingArtifacts(
            from: "Thank you... necesito ayuda con el reporte"
        )
        #expect(cleaned == "necesito ayuda con el reporte")
    }

    @Test("Drops isolated thank-you artifact")
    func dropsStandaloneThankYouArtifact() {
        let cleaned = TranscriptionEngine.sanitizedLeadingArtifacts(from: "thank you")
        #expect(cleaned.isEmpty)
    }

    @Test("Filters arbitrary bracketed text")
    func filtersArbitraryBrackets() {
        #expect(TranscriptionEngine.isHallucination("[anything here]"))
        #expect(TranscriptionEngine.isHallucination("(some sound)"))
    }

    // MARK: - Edge cases

    @Test("Filters very short text (< 3 chars)")
    func filtersShortText() {
        #expect(TranscriptionEngine.isHallucination(""))
        #expect(TranscriptionEngine.isHallucination("a"))
        #expect(TranscriptionEngine.isHallucination("ab"))
    }

    @Test("Filters pure punctuation")
    func filtersPunctuation() {
        #expect(TranscriptionEngine.isHallucination("..."))
        #expect(TranscriptionEngine.isHallucination("---"))
        #expect(TranscriptionEngine.isHallucination("!!!"))
    }

    @Test("Filters text with only whitespace after trim")
    func filtersWhitespace() {
        #expect(TranscriptionEngine.isHallucination("   "))
        #expect(TranscriptionEngine.isHallucination("\n\t"))
    }

    // MARK: - Valid text should NOT be filtered

    @Test("Does NOT filter normal Spanish speech")
    func passesNormalSpanish() {
        #expect(!TranscriptionEngine.isHallucination("Hola, ¿cómo estás?"))
        #expect(!TranscriptionEngine.isHallucination("Buenos días, necesito ayuda con esto."))
        #expect(!TranscriptionEngine.isHallucination("El proyecto está listo para revisión."))
    }

    @Test("Does NOT filter normal English speech")
    func passesNormalEnglish() {
        #expect(!TranscriptionEngine.isHallucination("Hello, how are you?"))
        #expect(!TranscriptionEngine.isHallucination("The meeting is at 3pm."))
        #expect(!TranscriptionEngine.isHallucination("Please send the report."))
    }

    @Test("Does NOT filter short but valid text (>= 3 chars)")
    func passesShortValid() {
        #expect(!TranscriptionEngine.isHallucination("yes"))
        #expect(!TranscriptionEngine.isHallucination("hola"))
        #expect(!TranscriptionEngine.isHallucination("ok!"))
    }

    @Test("Does NOT filter text containing brackets but with surrounding content")
    func passesTextWithBrackets() {
        // Text that happens to have brackets but is real speech
        #expect(!TranscriptionEngine.isHallucination("the array [1,2,3] is valid"))
    }

    // MARK: - False positive prevention (exact match vs contains)

    @Test("Does NOT filter text containing 'subscribe' as substring")
    func passesSubscribeInContext() {
        #expect(!TranscriptionEngine.isHallucination("I want to subscribe to the plan"))
        #expect(!TranscriptionEngine.isHallucination("Me quiero subscribir al servicio"))
    }

    @Test("Does NOT filter text containing 'subtítulos' as substring")
    func passesSubtitulosInContext() {
        #expect(!TranscriptionEngine.isHallucination("Los subtítulos están bien hechos"))
        #expect(!TranscriptionEngine.isHallucination("Necesito agregar subtítulos al video"))
    }

    @Test("Does NOT filter text containing 'gracias por ver' as substring")
    func passesGraciasPorVerInContext() {
        #expect(!TranscriptionEngine.isHallucination("Le dije gracias por ver el documento"))
    }

    @Test("Does NOT filter text containing 'thanks for watching' as substring")
    func passesThanksForWatchingInContext() {
        #expect(!TranscriptionEngine.isHallucination("He said thanks for watching the presentation"))
    }

    @Test("Does NOT filter text containing 'music' as regular word")
    func passesMusicAsWord() {
        #expect(!TranscriptionEngine.isHallucination("I love music and dancing"))
        #expect(!TranscriptionEngine.isHallucination("La música es mi pasión"))
    }

    @Test("Filters new hallucination phrases")
    func filtersNewPhrases() {
        #expect(TranscriptionEngine.isHallucination("suscríbete"))
        #expect(TranscriptionEngine.isHallucination("like and subscribe"))
        #expect(TranscriptionEngine.isHallucination("dale like"))
    }
}
