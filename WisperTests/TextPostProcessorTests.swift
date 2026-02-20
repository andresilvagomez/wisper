import Testing
@testable import Wisper

@Suite("Text Post Processor")
struct TextPostProcessorTests {
    @Test("Off mode only trims and keeps text literal")
    func offMode() {
        let result = TextPostProcessor.processFinal("   hola mundo   ", mode: .off)
        #expect(result == "hola mundo")
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
}
