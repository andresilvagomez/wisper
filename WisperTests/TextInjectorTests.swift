import Testing
@testable import Wisper

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

    @Test("recheckAccessibility updates the property")
    func recheckUpdates() {
        let injector = TextInjector()
        injector.recheckAccessibility()
        // In test environment, accessibility is typically false
        // This just verifies the method doesn't crash
        _ = injector.hasAccessibility
    }
}
