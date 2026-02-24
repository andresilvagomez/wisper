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
                .environmentObject(appState)
                .tabItem {
                    Label(L10n.t("About"), systemImage: "info.circle")
                }
        }
        .frame(minWidth: 660, minHeight: 420)
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

                Toggle(L10n.t("settings.mute_other_apps"), isOn: $appState.muteOtherAppsWhileRecording)

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
        .tint(.primary)
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

    private var modelButtonTitle: String {
        switch appState.modelPhase {
        case .downloading:
            return "Descargando..."
        case .loading:
            return "Preparando..."
        case .idle, .error:
            if appState.isModelInstalledLocally(appState.selectedModel) {
                return "Cargar modelo"
            }
            return "Descargar e instalar"
        case .ready:
            return "Modelo activo"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Motor de transcripción")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                settingsModelCard(
                    icon: "bolt.fill",
                    title: "Speex Turbo",
                    badge: "Recomendado",
                    badgeColor: .primary,
                    features: ["Rápido y muy preciso", "Funciona sin conexión", "Descarga ligera (~632 MB)"],
                    isSelected: appState.selectedModel == AppState.defaultBundledModelID,
                    isDisabled: appState.modelPhase.isActive || appState.isRecording,
                    isInstalled: appState.isModelInstalledLocally(AppState.defaultBundledModelID),
                    isActive: appState.selectedModel == AppState.defaultBundledModelID && appState.modelPhase.isReady
                ) {
                    appState.selectedModel = AppState.defaultBundledModelID
                }

                settingsModelCard(
                    icon: "sparkles",
                    title: "Speex Super Pro",
                    badge: "Máxima precisión",
                    badgeColor: .purple,
                    features: ["Máxima precisión por palabra", "Funciona sin conexión", "Para dictados extensos (~1.5 GB)"],
                    isSelected: appState.selectedModel == AppState.optionalSuperModelID,
                    isDisabled: appState.modelPhase.isActive || appState.isRecording,
                    isInstalled: appState.isModelInstalledLocally(AppState.optionalSuperModelID),
                    isActive: appState.selectedModel == AppState.optionalSuperModelID && appState.modelPhase.isReady
                ) {
                    appState.selectedModel = AppState.optionalSuperModelID
                }

                settingsModelCard(
                    icon: "cloud.fill",
                    title: "Cloud",
                    badge: "Próximamente",
                    badgeColor: .gray,
                    features: ["Sin usar espacio en tu Mac", "Siempre actualizado", "Disponible próximamente"],
                    isSelected: false,
                    isDisabled: true,
                    isInstalled: false,
                    isActive: false
                ) { }
            }

            settingsModelStatus

            if !appState.modelPhase.isReady {
                Button(modelButtonTitle) {
                    Task { await appState.loadModel() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.modelPhase.isActive || appState.isRecording)
            }

            Text(L10n.t("settings.model.info"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Model Card

    private func settingsModelCard(
        icon: String,
        title: String,
        badge: String,
        badgeColor: Color,
        features: [String],
        isSelected: Bool,
        isDisabled: Bool,
        isInstalled: Bool,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isDisabled ? Color.gray.gradient : badgeColor.gradient)
                    Spacer()
                    if isActive {
                        Label("En uso", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    } else if isInstalled {
                        Label("Instalado", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
                }

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDisabled ? .secondary : .primary)

                Text(badge)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12))
                    .foregroundColor(isDisabled ? .gray : badgeColor)
                    .clipShape(Capsule())

                Spacer(minLength: 2)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(isDisabled ? .gray : .green)
                            Text(feature)
                                .font(.caption2)
                                .foregroundStyle(isDisabled ? .tertiary : .secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? badgeColor.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? badgeColor : Color.secondary.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Model Status

    @ViewBuilder
    private var settingsModelStatus: some View {
        switch appState.modelPhase {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Descargando modelo...")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                ProgressView(value: progress)
                    .tint(.primary)
                Text(L10n.f("settings.model.downloading_percent", progress * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        case .loading(let step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(step)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 1)
            )
        case .ready:
            Label(L10n.t("settings.model.ready"), systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.callout)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .idle:
            if appState.isModelInstalledLocally(appState.selectedModel) {
                Label("Modelo descargado — listo para cargar", systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.primary)
                    .font(.callout)
            } else {
                Label("Se descargará al instalar", systemImage: "arrow.down.to.line")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
        }
    }
}

// MARK: - About

struct AboutTab: View {
    @EnvironmentObject var appState: AppState

    private var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
        return "v\(short)"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.primary)

            Text("Speex")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Speech to text, on device.")
                .foregroundColor(.secondary)

            Text(appVersionText)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button(L10n.t("settings.check_for_updates")) {
                appState.updateService.checkForUpdates()
            }
            .disabled(!appState.updateService.canCheckForUpdates)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
