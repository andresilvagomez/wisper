import ApplicationServices
import Carbon
import Cocoa
import Foundation

final class TextInjector: @unchecked Sendable {
    /// Inject text into the currently focused application via clipboard paste.
    /// This is the most reliable cross-app method for text injection on macOS.
    func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToInject = trimmed + " "
        print("[Wisper] TextInjector: injecting \(textToInject.count) chars: \"\(textToInject.prefix(50))\"")
        print("[Wisper] TextInjector: accessibility=\(isAccessibilityEnabled())")

        // Always use clipboard paste — most reliable method
        pasteViaClipboard(textToInject)
    }

    // MARK: - Clipboard Paste

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        usleep(50_000) // 50ms

        simulatePaste()
        print("[Wisper] TextInjector: paste command sent")

        // Restore previous clipboard after a delay
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), // 'v' key
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            print("[Wisper] TextInjector: ERROR - failed to create CGEvent")
            return
        }

        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand

        cmdVDown.post(tap: .cghidEventTap)
        usleep(10_000) // 10ms between key down/up
        cmdVUp.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility Check

    func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
