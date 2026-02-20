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
                    Label(L10n.t("General"), systemImage: "gear")
                }

            ModelSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label(L10n.t("Model"), systemImage: "brain")
                }

            AboutTab()
                .tabItem {
                    Label(L10n.t("About"), systemImage: "info.circle")
                }
        }
        .frame(minWidth: 520, minHeight: 380)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section(L10n.t("Language")) {
                Picker(L10n.t("Interface language"), selection: $appState.interfaceLanguage) {
                    ForEach(AppState.availableInterfaceLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Picker(L10n.t("Transcription language"), selection: $appState.selectedLanguage) {
                    ForEach(AppState.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: appState.selectedLanguage) { _, _ in
                    appState.reloadModel()
                }
            }

            Section(L10n.t("Recording")) {
                KeyboardShortcuts.Recorder(L10n.t("Shortcut"), name: HotkeyManager.shortcutName)

                Toggle(L10n.t("settings.whisper_mode"), isOn: $appState.whisperModeEnabled)

                if appState.hasMultipleInputDevices {
                    Picker(L10n.t("Input source"), selection: $appState.selectedInputDeviceUID) {
                        ForEach(appState.availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                }

                Picker(L10n.t("Mode"), selection: $appState.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }

                Picker(L10n.t("Text injection"), selection: $appState.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
            }

            Section(L10n.t("System")) {
                Toggle(L10n.t("Launch at login"), isOn: $appState.launchAtLogin)
                    .onChange(of: appState.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            appState.refreshInputDevices()
        }
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
            Section(L10n.t("settings.model.included.section")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("settings.model.included.title"))
                                .fontWeight(.semibold)
                            Text(L10n.t("settings.model.included.subtitle"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Label(L10n.t("settings.model.included.active"), systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }

                    if appState.selectedModel != AppState.defaultBundledModelID {
                        Button(L10n.t("settings.model.use_default")) {
                            appState.useDefaultBundledModel()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isRecording || appState.modelPhase.isActive)
                    }
                }
            }

            Section(L10n.t("settings.model.optional.section")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t("settings.model.optional.title"))
                                .fontWeight(.semibold)
                            Text(L10n.t("settings.model.optional.subtitle"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if appState.selectedModel == AppState.optionalSuperModelID, appState.modelPhase.isReady {
                            Label(L10n.t("settings.model.optional.in_use"), systemImage: "bolt.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else if appState.isModelInstalledLocally(AppState.optionalSuperModelID) {
                            Label(L10n.t("settings.model.optional.installed"), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Label(L10n.t("settings.model.optional.not_installed"), systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(appState.isModelInstalledLocally(AppState.optionalSuperModelID) ? L10n.t("settings.model.optional.use") : L10n.t("settings.model.optional.install_use")) {
                        appState.installAndUseSuperModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isRecording || appState.modelPhase.isActive)
                }
            }

            Section(L10n.t("settings.model.load_status")) {
                switch appState.modelPhase {
                case .downloading(let progress):
                    ProgressView(value: progress) {
                        Text(L10n.f("settings.model.downloading_percent", progress * 100))
                    }
                case .loading(let step):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(step)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .ready:
                    Label(L10n.t("settings.model.ready"), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .error(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                case .idle:
                    Text(L10n.t("settings.model.idle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(L10n.t("Info")) {
                Text(L10n.t("settings.model.info"))
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
    private var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
        return "v\(short)"
    }

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

            Text(appVersionText)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
