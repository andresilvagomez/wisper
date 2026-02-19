import KeyboardShortcuts
import Testing
import Foundation
@testable import Wisper

@Suite("Hotkey Manager")
struct HotkeyManagerTests {
    @Test("Manager persists default shortcut when none exists")
    func managerPersistsDefaultShortcut() {
        let defaultsKey = "KeyboardShortcuts_\(HotkeyManager.shortcutName.rawValue)"
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        _ = HotkeyManager(onKeyDown: {}, onKeyUp: {})

        let shortcut = KeyboardShortcuts.getShortcut(for: HotkeyManager.shortcutName)
        #expect(shortcut?.key == .space)
        #expect(shortcut?.modifiers.contains(.option) == true)
    }

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
