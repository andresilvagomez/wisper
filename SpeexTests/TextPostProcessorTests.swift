import Foundation
import Testing
@testable import Speex

@Suite("Text Post Processor")
struct TextPostProcessorTests {
    @Test("Off mode only trims and keeps text literal")
    func offMode() {
        let result = TextPostProcessor.processFinal("   hola mundo   ", mode: .off)
        #expect(result == "hola mundo")
    }

    @Test("Off mode removes spaces before punctuation marks")
    func offModePunctuationSpacing() {
        let result = TextPostProcessor.processFinal("hola coma mundo punto", mode: .off)
        #expect(result == "hola, mundo.")
    }

    @Test("Basic mode capitalizes and adds terminal punctuation")
    func basicMode() {
        let result = TextPostProcessor.processFinal("hola mundo", mode: .basic)
        #expect(result == "Hola mundo.")
    }

    @Test("Fluent mode removes filler words")
    func fluentMode() {
        let result = TextPostProcessor.processFinal("eh hola um mundo", mode: .fluent)
        #expect(result == "Hola mundo.")
    }

    @Test("Fluent mode maps dictated punctuation marks")
    func dictatedPunctuation() {
        let result = TextPostProcessor.processFinal("hola coma mundo signo de pregunta", mode: .fluent)
        #expect(result == "Hola, mundo?")
    }

    @Test("Chunk processing normalizes punctuation spacing")
    func chunkPunctuationSpacing() {
        let result = TextPostProcessor.processChunk("hola coma mundo", mode: .off, isFirstChunk: true)
        #expect(result == "hola, mundo")
    }

    @Test("Fluent mode maps dictated punctuation in multiple languages")
    func dictatedPunctuationMultilingual() {
        let result = TextPostProcessor.processFinal(
            "hello comma world point d'interrogation",
            mode: .fluent
        )
        #expect(result == "Hello, world?")
    }

    @Test("Pause separator chooses comma or period from gap")
    func pauseSeparator() {
        let base = Date(timeIntervalSince1970: 1_000)
        let comma = TextPostProcessor.separatorForPause(
            since: base,
            previousText: "hola",
            now: base.addingTimeInterval(0.7)
        )
        let period = TextPostProcessor.separatorForPause(
            since: base,
            previousText: "hola",
            now: base.addingTimeInterval(1.3)
        )

        #expect(comma == ", ")
        #expect(period == ". ")
    }

    @Test("Fluent mode formats detected numbered speech into list")
    func numberedListFormatting() {
        let input = "going to the store for 1. apples 2. bananas 3. oranges."
        let result = TextPostProcessor.processFinal(input, mode: .fluent)
        #expect(result == "1. Apples\n2. Bananas\n3. Oranges")
    }

    @Test("Spoken line and paragraph commands become line breaks")
    func spokenLineBreakCommands() {
        let input = "hola nueva línea esto es una prueba nuevo párrafo segunda parte"
        let result = TextPostProcessor.processFinal(input, mode: .fluent)
        #expect(result == "Hola\nEsto es una prueba\n\nSegunda parte.")
    }

    @Test("Correction command extracts replacement text")
    func correctionCommand() {
        let replacement = TextPostProcessor.correctionReplacementIfCommand(
            "no, quise decir vamos mañana"
        )
        #expect(replacement == "Vamos mañana.")
    }

    @Test("Replacing last sentence keeps previous confirmed content")
    func replaceLastSentence() {
        let original = "Vamos hoy. Llegamos tarde."
        let replaced = TextPostProcessor.replacingLastSentence(
            in: original,
            with: "Llegamos temprano."
        )
        #expect(replaced == "Vamos hoy. Llegamos temprano.")
    }

    @Test("Editing command detects delete last sentence")
    func detectDeleteLastSentenceCommand() {
        let cmd = TextPostProcessor.editingCommand(in: "borra última frase")
        #expect(cmd == .deleteLastSentence)
    }

    @Test("Editing command detects undo and redo")
    func detectUndoRedoCommands() {
        let undo = TextPostProcessor.editingCommand(in: "deshacer")
        let redo = TextPostProcessor.editingCommand(in: "rehacer")
        #expect(undo == .undo)
        #expect(redo == .redo)
    }

    @Test("Removing last sentence leaves previous sentence")
    func removeLastSentence() {
        let original = "Primera frase. Segunda frase."
        let updated = TextPostProcessor.removingLastSentence(from: original)
        #expect(updated == "Primera frase.")
    }
}
