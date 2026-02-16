import SwiftUI

struct TranscriptionOverlayContent: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseAnimation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )

                Text("Listening...")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "waveform")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Text content
            if !appState.confirmedText.isEmpty || !appState.partialText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !appState.confirmedText.isEmpty {
                        Text(appState.confirmedText)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    if !appState.partialText.isEmpty {
                        Text(appState.partialText)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                    }
                }
                .lineLimit(6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Speak now...")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    @MainActor
    func show(appState: AppState) {
        guard window == nil else { return }

        let content = TranscriptionOverlayContent()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 100)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.contentView = hostingView
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position near bottom-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 170
            let y = screenFrame.minY + 80
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)

        self.window = window
        self.hostingView = hostingView
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }
}
