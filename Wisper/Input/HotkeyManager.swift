import KeyboardShortcuts

final class HotkeyManager: @unchecked Sendable {
    private let onKeyDown: @Sendable () -> Void
    private let onKeyUp: @Sendable () -> Void

    static let shortcutName = KeyboardShortcuts.Name(
        "wisperRecordShortcut",
        default: .init(.space, modifiers: [.option])
    )

    init(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        KeyboardShortcuts.onKeyDown(for: Self.shortcutName) { [weak self] in
            self?.onKeyDown()
        }
        KeyboardShortcuts.onKeyUp(for: Self.shortcutName) { [weak self] in
            self?.onKeyUp()
        }
    }
}
