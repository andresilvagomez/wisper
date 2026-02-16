import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Model", systemImage: "brain")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 320)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Language") {
                Picker("Transcription language", selection: $appState.selectedLanguage) {
                    ForEach(AppState.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            }

            Section("Recording") {
                Picker("Mode", selection: $appState.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Text injection", selection: $appState.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $appState.launchAtLogin)
                    .onChange(of: appState.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                HStack {
                    Text("Accessibility")
                    Spacer()
                    if appState.textInjector?.isAccessibilityEnabled() == true {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            appState.textInjector?.requestAccessibility()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Settings] Launch at login error: \(error)")
        }
    }
}

// MARK: - Model Settings

struct ModelSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Whisper Model") {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(AppState.availableModels, id: \.id) { model in
                        VStack(alignment: .leading) {
                            Text(model.name)
                            Text(model.size)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(model.id)
                    }
                }

                switch appState.modelPhase {
                case .downloading(let progress):
                    ProgressView(value: progress) {
                        Text(String(format: "Downloading... %.1f%%", progress * 100))
                    }

                case .loading(let step):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(step)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .ready:
                    Label("Model loaded and ready", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)

                case .error(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Button("Retry") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)

                case .idle:
                    Button("Download & Load Model") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Info") {
                Text("Models are stored locally and run entirely on your Mac using Apple Silicon. No data is sent to the cloud.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)

            Text("Wisper")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Speech to text, on device.")
                .foregroundColor(.secondary)

            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
