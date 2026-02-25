import SwiftUI

@main
struct SpeexApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authService = AuthService()

    init() {
        CrashReporter.configureIfAvailable()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(authService)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
                .environmentObject(authService)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        }
        .menuBarExtraStyle(.window)

        Window(String(localized: "menu.settings"), id: "settings") {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(authService)
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
        .defaultSize(width: 760, height: 520)

        Window("Iniciar sesión", id: "auth") {
            AuthView()
                .environmentObject(authService)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 520)
    }
}

private struct MenuBarLabelView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authService: AuthService
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
            // Wait for Firebase to resolve initial auth state
            while authService.isLoading {
                try? await Task.sleep(for: .milliseconds(100))
            }

            guard authService.isAuthenticated else {
                openWindow(id: "auth")
                return
            }

            guard !hasPerformedInitialAudit else { return }
            hasPerformedInitialAudit = true
            await appState.runInitialPermissionAuditIfNeeded()
            presentOnboardingIfRequired()
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                if !hasPerformedInitialAudit {
                    hasPerformedInitialAudit = true
                    Task {
                        await appState.runInitialPermissionAuditIfNeeded()
                        presentOnboardingIfRequired()
                    }
                }
            } else {
                openWindow(id: "auth")
            }
        }
        .onChange(of: appState.onboardingPresentationToken) { _, _ in
            guard authService.isAuthenticated else { return }
            presentOnboardingIfRequired()
        }
    }

    private func presentOnboardingIfRequired() {
        guard !appState.hasCompletedOnboarding else { return }
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }
}
