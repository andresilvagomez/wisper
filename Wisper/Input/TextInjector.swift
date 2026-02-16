import ApplicationServices
import Cocoa
import Foundation

final class TextInjector: @unchecked Sendable {
    private let pasteQueue = DispatchQueue(label: "com.wisper.textinjector", qos: .userInteractive)
    private var hasShownAccessibilityHelper = false

    func setup() {
        let trusted = AXIsProcessTrusted()
        let bundlePath = Bundle.main.bundlePath
        print("[Wisper] TextInjector: bundle path = \(bundlePath)")
        print("[Wisper] TextInjector: accessibility = \(trusted)")

        if !trusted {
            print("[Wisper] ⚠️  Wisper needs Accessibility permission to paste text.")
            print("[Wisper] ⚠️  Opening Finder at the app location — drag it into")
            print("[Wisper] ⚠️  System Settings > Privacy & Security > Accessibility")

            // Open Finder highlighting the actual .app so user can drag it to Accessibility
            let url = URL(fileURLWithPath: bundlePath)
            NSWorkspace.shared.activateFileViewerSelecting([url])

            // Also open Accessibility settings
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(settingsURL)
            }

            hasShownAccessibilityHelper = true
        }
    }

    func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToInject = trimmed + " "

        print("")
        print("[Wisper] ========== TEXT OUTPUT ==========")
        print("[Wisper] \(textToInject)")
        print("[Wisper] =================================")
        print("")

        // Put text on clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToInject, forType: .string)

        // Paste via CGEvent Cmd+V
        pasteQueue.async {
            self.simulateCmdV()
        }
    }

    private func simulateCmdV() {
        usleep(50_000) // 50ms for clipboard

        let source = CGEventSource(stateID: .hidSystemState)

        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            print("[Wisper] TextInjector: ERROR creating CGEvent")
            return
        }

        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand

        cmdVDown.post(tap: .cghidEventTap)
        usleep(20_000) // 20ms
        cmdVUp.post(tap: .cghidEventTap)

        print("[Wisper] TextInjector: Cmd+V sent")
    }
}
