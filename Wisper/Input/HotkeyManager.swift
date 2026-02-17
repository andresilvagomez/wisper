import Carbon
import Cocoa
import HotKey

final class HotkeyManager: @unchecked Sendable {
    private var hotKey: HotKey?
    private let onKeyDown: @Sendable () -> Void
    private let onKeyUp: @Sendable () -> Void

    init(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        setupDefaultHotkey()
    }

    func setupDefaultHotkey() {
        setupHotkey(key: .space, modifiers: [.option])
    }

    func setupHotkey(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey?.isPaused = true
        hotKey = nil

        hotKey = HotKey(key: key, modifiers: modifiers)

        hotKey?.keyDownHandler = { [weak self] in
            self?.onKeyDown()
        }

        hotKey?.keyUpHandler = { [weak self] in
            self?.onKeyUp()
        }
    }

    deinit {
        hotKey?.isPaused = true
        hotKey = nil
    }
}
