import KeyboardShortcuts

final class HotkeyManager: @unchecked Sendable {
    private let onKeyDown: @Sendable () -> Void
    private let onKeyUp: @Sendable () -> Void

    static let shortcutName = KeyboardShortcuts.Name(
        "speexRecordShortcut",
        default: .init(.space, modifiers: [.option])
    )

    init(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        // KeyboardShortcuts only triggers for persisted shortcuts.
        // If nothing is saved yet, ensure the default is written.
        if KeyboardShortcuts.getShortcut(for: Self.shortcutName) == nil,
           let defaultShortcut = Self.shortcutName.defaultShortcut
        {
            KeyboardShortcuts.setShortcut(defaultShortcut, for: Self.shortcutName)
        }

        KeyboardShortcuts.onKeyDown(for: Self.shortcutName) { [weak self] in
            self?.onKeyDown()
        }
        KeyboardShortcuts.onKeyUp(for: Self.shortcutName) { [weak self] in
            self?.onKeyUp()
        }
    }
}
