import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            statusHeader

            Divider()

            // Current transcription preview
            if appState.isRecording || !appState.confirmedText.isEmpty {
                transcriptionPreview
                Divider()
            }

            // Model status
            modelStatus

            Divider()

            // Actions
            actionButtons
        }
        .frame(width: 320)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.headline)

            Spacer()

            Text("⌥ Space")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(12)
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        switch appState.modelPhase {
        case .ready: return .green
        case .downloading: return .blue
        case .loading: return .blue
        case .error: return .orange
        case .idle: return .gray
        }
    }

    private var statusText: String {
        if appState.isRecording { return "Recording..." }
        switch appState.modelPhase {
        case .ready:
            return "Ready"
        case .downloading(let progress):
            return String(format: "Downloading... %.1f%%", progress * 100)
        case .loading(let step):
            return step
        case .error:
            return "Error"
        case .idle:
            return "Model not loaded"
        }
    }

    // MARK: - Transcription Preview

    private var transcriptionPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transcription")
                .font(.caption)
                .foregroundColor(.secondary)

            Group {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Model Status

    private var modelStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(modelDisplayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    switch appState.modelPhase {
                    case .idle:
                        Text("Not loaded")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                    case .downloading(let progress):
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text(String(format: "Downloading... %.1f%%", progress * 100))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                    case .loading(let step):
                        ProgressView()
                            .controlSize(.small)
                        Text(step)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                    case .ready:
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)

                    case .error:
                        EmptyView()
                    }
                }

                Spacer()

                if case .idle = appState.modelPhase {
                    Button("Load") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let error = appState.modelPhase.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(3)
                }

                Button("Retry") {
                    Task { await appState.loadModel() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var modelDisplayName: String {
        AppState.availableModels.first { $0.id == appState.selectedModel }?.name
            ?? appState.selectedModel
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 0) {
            Button(action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("Accessibility Permissions", systemImage: "hand.raised")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
