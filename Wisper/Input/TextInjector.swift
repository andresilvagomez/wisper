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

    func typeText(_ text: String, clipboardAfterInjection: String? = nil) {
        guard !text.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToInject = trimmed + " "
        setClipboard(textToInject, synchronously: true)

        hasAccessibility = AXIsProcessTrusted()
        print("[Wisper] 📋 typeText: \"\(textToInject)\" | accessibility=\(hasAccessibility) | target=\(targetApp?.localizedName ?? "none")")

        guard hasAccessibility else {
            print("[Wisper] ⚠️ Skipping paste — no Accessibility permission")
            return
        }

        let app = resolvedTargetApp()

        pasteQueue.async {
            // 1. Activate target app first
            if let app {
                app.activate(options: [.activateIgnoringOtherApps])
                usleep(220_000) // let app/window become active
            }

            // 2. Try direct AX insertion (primary)
            if self.injectTextViaAccessibility(textToInject) {
                print("[Wisper] ✅ Injected via AXSelectedTextAttribute")
                if let clipboardAfterInjection {
                    self.setClipboard(clipboardAfterInjection)
                }
                return
            }

            print("[Wisper] ↩️ Falling back to clipboard + Cmd+V")

            // 3. Simulate Cmd+V (clipboard already set above)
            self.simulateCmdV()

            if let clipboardAfterInjection {
                self.setClipboard(clipboardAfterInjection, delay: 0.12)
            }
        }
    }

    func copyAccumulatedTextToClipboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setClipboard(trimmed, synchronously: true)
    }

    private func setClipboard(_ text: String, synchronously: Bool = false, delay: TimeInterval = 0) {
        let write = {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("[Wisper] 📋 Clipboard updated (\(text.count) chars)")
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                write()
            }
            return
        }

        if synchronously {
            if Thread.isMainThread {
                write()
            } else {
                DispatchQueue.main.sync {
                    write()
                }
            }
        } else {
            DispatchQueue.main.async {
                write()
            }
        }
    }

    private func resolvedTargetApp() -> NSRunningApplication? {
        if let targetApp,
           targetApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            return targetApp
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        return frontmost
    }

    private func injectTextViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard status == .success else {
            print("[Wisper] AX focus lookup failed: \(status.rawValue)")
            return false
        }

        guard let focusedRef else {
            print("[Wisper] AX focused element unavailable")
            return false
        }
        let focusedElement = unsafeBitCast(focusedRef, to: AXUIElement.self)

        let setStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        guard setStatus == .success else {
            print("[Wisper] AX insert failed: \(setStatus.rawValue)")
            return false
        }

        return true
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

        cmdVDown.post(tap: .cgAnnotatedSessionEventTap)
        cmdVDown.post(tap: .cghidEventTap)
        usleep(20_000)
        cmdVUp.post(tap: .cgAnnotatedSessionEventTap)
        cmdVUp.post(tap: .cghidEventTap)

        print("[Wisper] TextInjector: Cmd+V sent")
    }
}
