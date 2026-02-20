import Testing
@testable import Speex

@Suite("Dictation Editing Service")
struct DictationEditingServiceTests {
    @Test("Delete last sentence snapshots state and trims text")
    func deleteLastSentence() {
        let service = DictationEditingService()
        let original = "Primera frase. Segunda frase."

        let updated = service.applyCommand(.deleteLastSentence, currentText: original)
        #expect(updated == "Primera frase.")

        let undone = service.applyCommand(.undo, currentText: updated ?? "")
        #expect(undone == original)
    }

    @Test("Undo and redo cycle works with snapshot")
    func undoRedoCycle() {
        let service = DictationEditingService()
        service.snapshot(currentText: "Hola")
        let undo = service.applyCommand(.undo, currentText: "Hola mundo")
        #expect(undo == "Hola")

        let redo = service.applyCommand(.redo, currentText: "Hola")
        #expect(redo == "Hola mundo")
    }

    @Test("Reset clears history")
    func resetHistory() {
        let service = DictationEditingService()
        service.snapshot(currentText: "a")
        service.reset()

        let undo = service.applyCommand(.undo, currentText: "b")
        #expect(undo == nil)
    }
}
