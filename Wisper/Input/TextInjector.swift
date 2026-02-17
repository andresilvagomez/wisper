import ApplicationServices
import Cocoa
import Foundation

final class TextInjector: @unchecked Sendable {
    private let pasteQueue = DispatchQueue(label: "com.wisper.textinjector", qos: .userInteractive)

    /// The app that was active when recording started — paste goes here.
    private var targetApp: NSRunningApplication?

    /// Whether we have Accessibility permission (checked on setup and each paste)
    private(set) var hasAccessibility: Bool = false

    func setup() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        print("[Wisper] TextInjector: accessibility = \(hasAccessibility)")
    }

    func recheckAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func captureTargetApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
        print("[Wisper] TextInjector: target app = \(targetApp?.localizedName ?? "none") (pid: \(targetApp?.processIdentifier ?? 0))")
    }

    func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToInject = trimmed + " "

        hasAccessibility = AXIsProcessTrusted()
        print("[Wisper] 📋 typeText: \"\(textToInject)\" | accessibility=\(hasAccessibility) | target=\(targetApp?.localizedName ?? "none")")

        guard hasAccessibility else {
            print("[Wisper] ⚠️ Skipping paste — no Accessibility permission")
            return
        }

        let app = targetApp

        pasteQueue.async {
            // 1. Copy to clipboard first (always)
            DispatchQueue.main.sync {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(textToInject, forType: .string)
            }
            print("[Wisper] 📋 Clipboard set")

            // 2. Activate target app
            if let app {
                app.activate()
                usleep(200_000) // 200ms for app to come to front
            }

            // 3. Simulate Cmd+V
            self.simulateCmdV()
        }
    }

    // MARK: - Clipboard + Cmd+V

    private func simulateCmdV() {
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
        usleep(20_000)
        cmdVUp.post(tap: .cghidEventTap)

        print("[Wisper] TextInjector: Cmd+V sent")
    }
}
