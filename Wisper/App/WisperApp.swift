import SwiftUI

@main
struct WisperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        } label: {
            Label {
                Text("Wisper")
            } icon: {
                Image(systemName: appState.isRecording ? "waveform.circle.fill" : "mic.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(appState.isRecording ? .red : .primary)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        }

        Window(String(localized: "window.onboarding.title"), id: "onboarding") {
            OnboardingView()
                .environmentObject(appState)
                .environment(\.locale, Locale(identifier: appState.resolvedInterfaceLanguageCode))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
    }
}
