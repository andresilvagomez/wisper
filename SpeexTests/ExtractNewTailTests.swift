import Testing
@testable import Speex

@Suite("Extract New Tail")
struct ExtractNewTailTests {

    // MARK: - Basic delta extraction

    @Test("Extracts missing tail after sentence boundary")
    func extractsTailAfterSentenceBoundary() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Tiene que ser muy fiables de las cosas. que se necesitan acá.",
            alreadyConfirmed: "Tiene que ser muy fiables de las cosas."
        )
        #expect(result == "que se necesitan acá.")
    }

    @Test("Extracts tail when confirmed text is prefix of retranscription")
    func extractsTailFromPrefix() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "vamos a probar el contexto y de que al final si termine funcionando bien",
            alreadyConfirmed: "vamos a probar el contexto y de que al final"
        )
        #expect(result == "si termine funcionando bien")
    }

    @Test("Extracts tail from longer retranscription with partial overlap")
    func extractsTailPartialOverlap() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "probar ahora la traducción. Tiene que ser muy fiables de las cosas. que se necesitan acá.",
            alreadyConfirmed: "Bueno, vamos a probar ahora la traducción. Tiene que ser muy fiables de las cosas."
        )
        #expect(result == "que se necesitan acá.")
    }

    // MARK: - Edge cases

    @Test("Returns full text when confirmed is empty")
    func returnsFullWhenConfirmedEmpty() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Hola mundo",
            alreadyConfirmed: ""
        )
        #expect(result == "Hola mundo")
    }

    @Test("Returns nil when retranscribed is empty")
    func returnsNilWhenRetranscribedEmpty() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "",
            alreadyConfirmed: "algo confirmado"
        )
        #expect(result == nil)
    }

    @Test("Returns nil when retranscription matches confirmed exactly")
    func returnsNilWhenExactMatch() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Hola, esto es una prueba.",
            alreadyConfirmed: "Hola, esto es una prueba."
        )
        #expect(result == nil)
    }

    @Test("Returns full text when no anchor found")
    func returnsFallbackWhenNoAnchor() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Texto completamente diferente aquí",
            alreadyConfirmed: "Nada que ver con lo anterior"
        )
        #expect(result == "Texto completamente diferente aquí")
    }

    @Test("Returns full text when confirmed has only one word")
    func returnsFallbackWithSingleWordConfirmed() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Hola mundo bonito",
            alreadyConfirmed: "Hola"
        )
        #expect(result == "Hola mundo bonito")
    }

    // MARK: - Punctuation tolerance

    @Test("Matches ignoring trailing punctuation differences")
    func matchesIgnoringPunctuation() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "de las cosas que se necesitan",
            alreadyConfirmed: "de las cosas."
        )
        #expect(result == "que se necesitan")
    }

    @Test("Handles comma vs period differences")
    func handlesCommaPeriodDifferences() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "es muy importante, que hagamos esto bien",
            alreadyConfirmed: "es muy importante."
        )
        #expect(result == "que hagamos esto bien")
    }

    // MARK: - Case insensitivity

    @Test("Matches case-insensitively")
    func matchesCaseInsensitive() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Las Cosas que se necesitan acá",
            alreadyConfirmed: "las cosas"
        )
        #expect(result == "que se necesitan acá")
    }

    // MARK: - Real-world scenarios from user reports

    @Test("Recovers 'si termine funcionando bien' from user report")
    func recoversUserReport1() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Ok, ahora sí vamos a probar el contexto y de que al final si termine funcionando bien",
            alreadyConfirmed: "Ok, ahora sí vamos a probar el contexto y de que al final"
        )
        #expect(result == "si termine funcionando bien")
    }

    @Test("Recovers 'que se necesitan aca' from user report")
    func recoversUserReport2() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "Bueno, vamos a probar ahora la traducción. Tiene que ser muy fiables de las cosas. que se necesitan aca",
            alreadyConfirmed: "Bueno, vamos a probar ahora la traducción. Tiene que ser muy fiables de las cosas."
        )
        #expect(result == "que se necesitan aca")
    }

    // MARK: - Anchor robustness

    @Test("Uses longest possible anchor for accurate matching")
    func usesLongestAnchor() {
        // "de las" appears twice, but the longer anchor "fiables de las cosas" is unique
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "una de las razones, fiables de las cosas que faltan aquí",
            alreadyConfirmed: "Tiene que ser fiables de las cosas."
        )
        #expect(result == "que faltan aquí")
    }

    @Test("Handles retranscription that starts mid-sentence")
    func handlesRetranscriptionMidSentence() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "traducción. Tiene que ser muy fiables de las cosas. que se necesitan.",
            alreadyConfirmed: "Bueno, vamos a probar ahora la traducción. Tiene que ser muy fiables de las cosas."
        )
        #expect(result == "que se necesitan.")
    }

    // MARK: - Short texts

    @Test("Works with two-word anchor")
    func worksTwoWordAnchor() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "texto anterior más cosas nuevas",
            alreadyConfirmed: "texto anterior"
        )
        #expect(result == "más cosas nuevas")
    }

    @Test("Returns full when both texts have single word")
    func singleWordBoth() {
        let result = TranscriptionEngine.extractNewTail(
            retranscribed: "hola",
            alreadyConfirmed: "hola"
        )
        // Single word confirmed < 2 words, falls through to full return
        #expect(result == "hola")
    }
}
