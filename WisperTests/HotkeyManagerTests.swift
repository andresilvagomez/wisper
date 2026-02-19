import KeyboardShortcuts
import Testing
@testable import Wisper

@Suite("Hotkey Manager")
struct HotkeyManagerTests {
    @Test("Shortcut name is stable")
    func shortcutNameIsStable() {
        #expect(HotkeyManager.shortcutName.rawValue == "wisperRecordShortcut")
    }

    @Test("Default shortcut is Option + Space")
    func defaultShortcut() {
        let shortcut = HotkeyManager.shortcutName.defaultShortcut
        #expect(shortcut?.key == .space)
        #expect(shortcut?.modifiers.contains(.option) == true)
    }
}
