import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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

            // Language selector
            languageSelector
            Divider()

            // Actions
            actionButtons
        }
        .frame(width: 280)
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

            Text("⌥ Space")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
        .padding(12)
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        switch appState.modelPhase {
        case .ready: return .green
        case .downloading, .loading: return .blue
        case .error: return .orange
        case .idle: return .gray
        }
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        switch appState.modelPhase {
        case .ready: return "Ready"
        case .downloading(let p):
            return String(format: "Downloading... %.0f%%", p * 100)
        case .loading(let step): return step
        case .error: return "Error loading model"
        case .idle: return "Starting..."
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
            if !appState.confirmedText.isEmpty {
                Text(appState.confirmedText)
                    .foregroundColor(.primary)
            }
            if !appState.partialText.isEmpty {
                Text(appState.partialText)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .font(.system(.body, design: .rounded))
        .lineLimit(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Language Selector

    private var languageSelector: some View {
        Picker(selection: $appState.selectedLanguage) {
            ForEach(AppState.availableLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        } label: {
            Label("Language", systemImage: "globe")
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

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

            SettingsLink {
                Label("Settings...", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit Wisper", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .keyboardShortcut("q")
        }
    }
}
