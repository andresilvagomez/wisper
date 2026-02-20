import SwiftUI

// MARK: - Non-Activating Panel

/// NSPanel that NEVER becomes key or main — guaranteed to not steal focus.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum OverlayPositioning {
    private static let margin: CGFloat = 12

    static func defaultOrigin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        let x = visibleFrame.midX - (panelSize.width / 2)
        let y = visibleFrame.minY + 60
        return clampedOrigin(desired: NSPoint(x: x, y: y), panelSize: panelSize, visibleFrame: visibleFrame)
    }

    static func clampedOrigin(desired: NSPoint, panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - panelSize.width - margin
        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - panelSize.height - margin

        return NSPoint(
            x: min(max(desired.x, minX), maxX),
            y: min(max(desired.y, minY), maxY)
        )
    }
}

struct OverlayPositionStorage {
    private let defaults: UserDefaults
    private let keyX = "overlayWindowOriginX"
    private let keyY = "overlayWindowOriginY"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NSPoint? {
        guard let x = defaults.object(forKey: keyX) as? Double,
              let y = defaults.object(forKey: keyY) as? Double else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    func save(_ origin: NSPoint) {
        defaults.set(Double(origin.x), forKey: keyX)
        defaults.set(Double(origin.y), forKey: keyY)
    }

    func clear() {
        defaults.removeObject(forKey: keyX)
        defaults.removeObject(forKey: keyY)
    }
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
    let onResetPosition: (() -> Void)?
    let onDragChanged: ((CGSize) -> Void)?
    let onDragEnded: (() -> Void)?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { column in
                            Circle()
                                .fill(Color.primary.opacity(0.75))
                                .frame(width: 3.5, height: 3.5)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(width: 20, height: 22)
            .contentShape(Rectangle())
            .help("Drag to move")
            .onTapGesture(count: 2) {
                onResetPosition?()
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onDragChanged?(value.translation)
                    }
                    .onEnded { _ in
                        onDragEnded?()
                    }
            )

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

            if appState.hasMultipleInputDevices {
                Menu {
                    ForEach(appState.availableInputDevices) { device in
                        Button {
                            appState.selectedInputDeviceUID = device.id
                        } label: {
                            if device.id == appState.selectedInputDeviceUID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                        Text(appState.selectedInputDeviceName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 140)
                }
                .menuStyle(.borderlessButton)
            }

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
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
        .onAppear {
            pulse = true
            appState.refreshInputDevices()
        }
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController {
    private var window: FloatingPanel?
    private let positionStorage = OverlayPositionStorage()
    private var dragInitialOrigin: NSPoint?

    @MainActor
    func show(appState: AppState) {
        guard window == nil else { return }

        // Remember which app is active BEFORE we show anything
        let previousApp = NSWorkspace.shared.frontmostApplication

        let contentHeight: CGFloat = 48
        let contentWidth: CGFloat = appState.hasMultipleInputDevices ? 360 : 200

        let content = RecordingIndicatorContent(
            onResetPosition: { [weak self] in
                self?.resetToDefaultPosition()
            },
            onDragChanged: { [weak self] translation in
                self?.handleDragChanged(translation: translation)
            },
            onDragEnded: { [weak self] in
                self?.handleDragEnded()
            }
        )
            .environmentObject(appState)

        let panelWidth = contentWidth
        let panelHeight = contentHeight
        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.hasShadow = false
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let savedOrigin = positionStorage.load()
            let desiredOrigin = savedOrigin ?? OverlayPositioning.defaultOrigin(
                panelSize: CGSize(width: panelWidth, height: panelHeight),
                visibleFrame: screenFrame
            )
            let clampedOrigin = OverlayPositioning.clampedOrigin(
                desired: desiredOrigin,
                panelSize: CGSize(width: panelWidth, height: panelHeight),
                visibleFrame: screenFrame
            )
            panel.setFrameOrigin(clampedOrigin)
        }

        panel.orderFrontRegardless()
        self.window = panel

        // Reactivate the previous app to guarantee focus is not stolen
        previousApp?.activate()
    }

    @MainActor
    func hide() {
        dragInitialOrigin = nil
        window?.orderOut(nil)
        window = nil
    }

    @MainActor
    private func resetToDefaultPosition() {
        guard let window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let panelSize = window.frame.size
        let defaultOrigin = OverlayPositioning.defaultOrigin(
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        positionStorage.clear()
        window.setFrameOrigin(defaultOrigin)
        positionStorage.save(defaultOrigin)
    }

    @MainActor
    private func handleDragChanged(translation: CGSize) {
        guard let window else { return }

        if dragInitialOrigin == nil {
            dragInitialOrigin = window.frame.origin
        }

        guard let initialOrigin = dragInitialOrigin else { return }
        let desiredOrigin = NSPoint(
            x: initialOrigin.x + translation.width,
            y: initialOrigin.y - translation.height
        )

        if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            let clampedOrigin = OverlayPositioning.clampedOrigin(
                desired: desiredOrigin,
                panelSize: window.frame.size,
                visibleFrame: visibleFrame
            )
            window.setFrameOrigin(clampedOrigin)
        } else {
            window.setFrameOrigin(desiredOrigin)
        }
    }

    @MainActor
    private func handleDragEnded() {
        guard let window else { return }
        dragInitialOrigin = nil
        positionStorage.save(window.frame.origin)
    }
}
