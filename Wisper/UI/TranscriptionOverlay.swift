import SwiftUI

// MARK: - Non-Activating Panel

/// NSPanel that NEVER becomes key or main — guaranteed to not steal focus.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Audio Wave Bars

struct AudioWaveView: View {
    let audioLevel: Float
    let barCount = 5
    @State private var animatedLevels: [CGFloat] = Array(repeating: 0.15, count: 5)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 3, height: max(4, animatedLevels[index] * 24))
            }
        }
        .frame(height: 24)
        .onChange(of: audioLevel) { _, newLevel in
            withAnimation(.easeOut(duration: 0.1)) {
                for i in 0..<barCount {
                    let variation = Float.random(in: 0.6...1.4)
                    let level = CGFloat(newLevel * variation)
                    animatedLevels[i] = max(0.15, min(1.0, level))
                }
            }
        }
    }
}

// MARK: - Recording Indicator Content

struct RecordingIndicatorContent: View {
    @EnvironmentObject var appState: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0.7 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulse
                )

            AudioWaveView(audioLevel: appState.audioLevel)

            Image(systemName: "stop.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.red.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture {
                    appState.toggleRecording()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .onAppear { pulse = true }
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController {
    private var window: FloatingPanel?

    @MainActor
    func show(appState: AppState) {
        guard window == nil else { return }

        // Remember which app is active BEFORE we show anything
        let previousApp = NSWorkspace.shared.frontmostApplication

        let content = RecordingIndicatorContent()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 48)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 100
            let y = screenFrame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.window = panel

        // Reactivate the previous app to guarantee focus is not stolen
        previousApp?.activate()
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
