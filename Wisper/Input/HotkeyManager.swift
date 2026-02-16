import Carbon
import Cocoa
import HotKey

final class HotkeyManager: @unchecked Sendable {
    private var hotKey: HotKey?
    private let onToggle: @Sendable () -> Void
    private var isActive = false

    init(
        onToggle: @escaping @Sendable () -> Void
    ) {
        self.onToggle = onToggle
        setupDefaultHotkey()
    }

    func setupDefaultHotkey() {
        setupHotkey(key: .space, modifiers: [.option])
    }

    func setupHotkey(key: Key, modifiers: NSEvent.ModifierFlags) {
        hotKey?.isPaused = true
        hotKey = nil

        hotKey = HotKey(key: key, modifiers: modifiers)

        // Toggle mode: press once to start, press again to stop
        hotKey?.keyDownHandler = { [weak self] in
            self?.onToggle()
        }
    }

    deinit {
        hotKey?.isPaused = true
        hotKey = nil
    }
}
