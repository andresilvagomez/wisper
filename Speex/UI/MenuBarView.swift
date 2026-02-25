import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authService: AuthService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !authService.isAuthenticated {
            notSignedInView
        } else {
            authenticatedContent
        }
    }

    // MARK: - Not Signed In

    private var notSignedInView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text("Inicia sesión para usar Speex")
                .font(.callout)
                .foregroundColor(.secondary)

            Button("Iniciar sesión") {
                openWindow(id: "auth")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 280)
    }

    // MARK: - Authenticated Content

    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            statusHeader

            // Progress bar only when downloading/loading
            if appState.modelPhase.isActive {
                modelProgress
                Divider()
            }

            // Transcription preview while recording
            if appState.isRecording || !appState.confirmedText.isEmpty {
                transcriptionPreview
                Divider()
            }

            // Permission warnings
            if appState.needsMicrophone {
                microphoneWarning
                Divider()
            }
            if appState.needsAccessibility {
                accessibilityWarning
                Divider()
            }

            // Language selector
            languageSelector
            Divider()

            if appState.hasMultipleInputDevices {
                inputSourceSelector
                Divider()
            }

            // Actions
            actionButtons
        }
        .frame(width: 280)
        .onAppear {
            appState.refreshInputDevices()
            appState.ensureModelWarmInBackground(reason: "menu_opened")
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.system(.body, weight: .medium))

            Spacer()

            Text(currentShortcutLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
        .padding(12)
    }

    private var currentShortcutLabel: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: HotkeyManager.shortcutName) {
            return shortcut.description
        }

        return L10n.t("menu.no_shortcut")
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        switch appState.modelPhase {
        case .ready: return .green
        case .downloading, .loading: return .secondary
        case .error: return .orange
        case .idle: return .gray
        }
    }

    private var statusText: String {
        if appState.isRecording { return L10n.t("menu.status.recording") }
        switch appState.modelPhase {
        case .ready: return L10n.t("menu.status.ready")
        case .downloading(let p):
            return L10n.f("menu.status.downloading_percent", p * 100)
        case .loading(let step): return step
        case .error: return L10n.t("menu.status.error_loading_model")
        case .idle: return L10n.t("menu.status.starting")
        }
    }

    // MARK: - Model Progress (only during download/load)

    private var modelProgress: some View {
        VStack(spacing: 6) {
            if case .downloading(let progress) = appState.modelPhase {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Transcription Preview

    private var transcriptionPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("Transcription"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !appState.confirmedText.isEmpty {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.confirmedText.trimmingCharacters(in: .whitespaces), forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help(L10n.t("Copy transcription"))
                }
            }

            if !appState.confirmedText.isEmpty {
                Text(appState.confirmedText)
                    .foregroundColor(.primary)
            }
            if !appState.partialText.isEmpty {
                Text(appState.partialText)
                    .foregroundColor(.secondary)
                    .italic()
            }

            if appState.runtimeMetrics.chunkCount > 0 {
                Text(runtimeMetricsSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(.body, design: .rounded))
        .lineLimit(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var runtimeMetricsSummary: String {
        let metrics = appState.runtimeMetrics
        let ttfx = metrics.firstTextLatencyMs ?? 0
        let avg = metrics.averageChunkProcessingMs ?? 0
        return L10n.f(
            "menu.metrics.summary",
            ttfx,
            metrics.chunkCount,
            avg
        )
    }

    // MARK: - Language Selector

    private var languageSelector: some View {
        Picker(selection: $appState.selectedLanguage) {
            ForEach(LanguageCatalog.availableLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        } label: {
            Label("Transcription language", systemImage: "globe")
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: appState.selectedLanguage) { _, _ in
            appState.reloadModel()
        }
    }

    // MARK: - Accessibility Warning

    private var accessibilityWarning: some View {
        Button(action: {
            openGuidedOnboarding()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Falta Accesibilidad"))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(L10n.t("menu.permissions.open_guide"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Microphone Warning

    private var microphoneWarning: some View {
        Button(action: {
            openGuidedOnboarding()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Falta Micrófono"))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(L10n.t("menu.permissions.open_guide"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private var inputSourceSelector: some View {
        Picker(selection: $appState.selectedInputDeviceUID) {
            ForEach(appState.availableInputDevices) { device in
                Text(device.name).tag(device.id)
            }
        } label: {
            Label("Input source", systemImage: "mic.fill")
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var actionButtons: some View {
        VStack(spacing: 0) {
            if let error = appState.modelPhase.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
            }

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }) {
                Label(L10n.t("menu.settings"), systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button(action: {
                appState.cleanup()
                NSApplication.shared.terminate(nil)
            }) {
                Label(L10n.t("menu.quit"), systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .keyboardShortcut("q")
        }
    }

    private func openGuidedOnboarding() {
        appState.requestOnboardingPresentation()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }
}
