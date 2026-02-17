import ApplicationServices
import Cocoa
import Foundation

final class TextInjector: @unchecked Sendable {
    private let pasteQueue = DispatchQueue(label: "com.wisper.textinjector", qos: .userInteractive)

    /// The app that was active when recording started — paste goes here.
    private var targetApp: NSRunningApplication?

    func setup() {
        let trusted = AXIsProcessTrusted()
        print("[Wisper] TextInjector: accessibility = \(trusted)")
        print("[Wisper] TextInjector: bundle path = \(Bundle.main.bundlePath)")
    }

    /// Call this when recording starts to capture which app should receive the text.
    func captureTargetApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
        print("[Wisper] TextInjector: target app = \(targetApp?.localizedName ?? "none") (pid: \(targetApp?.processIdentifier ?? 0))")
    }

    func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToInject = trimmed + " "

        // Diagnostic: check Accessibility every time we try to paste
        let trusted = AXIsProcessTrusted()
        print("")
        print("[Wisper] ========== TEXT OUTPUT ==========")
        print("[Wisper] text: \(textToInject)")
        print("[Wisper] accessibility: \(trusted)")
        print("[Wisper] target: \(targetApp?.localizedName ?? "none") (pid: \(targetApp?.processIdentifier ?? 0))")
        if !trusted {
            print("[Wisper] ⚠️ Accessibility NOT granted — Cmd+V will fail silently!")
            print("[Wisper] ⚠️ Add this binary to System Settings > Privacy > Accessibility:")
            print("[Wisper] ⚠️ \(Bundle.main.bundlePath)")
        }
        print("[Wisper] =================================")
        print("")

        // Put text on clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToInject, forType: .string)

        let app = targetApp

        pasteQueue.async {
            if let app {
                let activated = app.activate()
                print("[Wisper] TextInjector: activate(\(app.localizedName ?? "?")) = \(activated)")
                usleep(200_000) // 200ms for app to gain focus
            } else {
                print("[Wisper] TextInjector: no target app, pasting to frontmost")
                usleep(50_000)
            }

            self.simulateCmdV()
        }
    }

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
        usleep(20_000) // 20ms
        cmdVUp.post(tap: .cghidEventTap)

        print("[Wisper] TextInjector: Cmd+V sent")
    }
}
