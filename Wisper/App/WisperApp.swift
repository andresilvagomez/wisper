import SwiftUI

@main
struct WisperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
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
        }

        Window(String(localized: "window.onboarding.title"), id: "onboarding") {
            OnboardingView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
    }
}
