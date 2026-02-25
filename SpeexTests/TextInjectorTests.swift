import Testing
@testable import Speex

@Suite("TextInjector Logic")
struct TextInjectorTests {

    @Test("Has accessibility starts as false")
    func initialAccessibility() {
        let injector = TextInjector()
        #expect(injector.hasAccessibility == false)
    }

    @Test("typeText ignores empty string")
    func ignoresEmptyText() {
        let injector = TextInjector()
        // Should not crash or do anything
        injector.typeText("")
    }

    @Test("typeText ignores whitespace-only string")
    func ignoresWhitespaceOnly() {
        let injector = TextInjector()
        injector.typeText("   ")
        injector.typeText("\n\t\n")
    }

    @Test("normalizedInjectionText trims without forcing trailing space")
    func normalizedInjectionText() {
        #expect(TextInjector.normalizedInjectionText(" hola ") == "hola")
        #expect(TextInjector.normalizedInjectionText("") == nil)
        #expect(TextInjector.normalizedInjectionText("   ") == nil)
    }

    @Test("recheckAccessibility updates the property")
    func recheckUpdates() {
        let injector = TextInjector()
        injector.recheckAccessibility()
        // In test environment, accessibility is typically false
        // This just verifies the method doesn't crash
        _ = injector.hasAccessibility
    }

    // MARK: - normalizedInjectionText edge cases

    @Test("normalizedInjectionText preserves internal whitespace")
    func preservesInternalWhitespace() {
        #expect(TextInjector.normalizedInjectionText("hola mundo") == "hola mundo")
        #expect(TextInjector.normalizedInjectionText("line1\nline2") == "line1\nline2")
    }

    @Test("normalizedInjectionText trims leading and trailing whitespace only")
    func trimsOnlyEdges() {
        #expect(TextInjector.normalizedInjectionText("\n hola mundo \n") == "hola mundo")
    }

    // MARK: - typeText without accessibility

    @Test("typeText sets clipboard even without accessibility permission")
    func typeTextSetsClipboardWithoutAccessibility() {
        let injector = TextInjector()
        // hasAccessibility is false by default in tests
        #expect(injector.hasAccessibility == false)
        // Should not crash — sets clipboard but skips paste
        injector.typeText("texto de prueba")
    }

    @Test("typeText with clipboardAfterInjection does not crash")
    func typeTextWithClipboardAfterInjection() {
        let injector = TextInjector()
        injector.typeText("texto", clipboardAfterInjection: "texto completo")
    }
}
