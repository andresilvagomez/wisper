import SwiftUI

@main
struct SpeexApp: App {
    @StateObject private var appState = AppState()

    init() {
        CrashReporter.configureIfAvailable()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        }
        .menuBarExtraStyle(.window)

        Window(String(localized: "menu.settings"), id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        }
        .defaultSize(width: 520, height: 380)
        .windowResizability(.contentMinSize)

        Window(String(localized: "window.onboarding.title"), id: "onboarding") {
            OnboardingView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
    }
}

private struct MenuBarLabelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var hasPerformedInitialAudit = false

    var body: some View {
        Label {
            Text("Speex")
        } icon: {
            Image(systemName: appState.isRecording ? "waveform.circle.fill" : "mic.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.isRecording ? .red : .primary)
        }
        .task {
            guard !hasPerformedInitialAudit else { return }
            hasPerformedInitialAudit = true
            await appState.runInitialPermissionAuditIfNeeded()
            presentOnboardingIfRequired()
        }
        .onChange(of: appState.onboardingPresentationToken) { _, _ in
            presentOnboardingIfRequired()
        }
    }

    private func presentOnboardingIfRequired() {
        guard appState.needsAccessibility || appState.needsMicrophone else { return }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }
}
