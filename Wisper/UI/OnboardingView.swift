import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                permissionsStep.tag(1)
                modelStep.tag(2)
            }
            .tabViewStyle(.automatic)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                if currentStep < 2 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else if appState.modelPhase.isReady {
                    Button("Get Started") {
                        appState.hasCompletedOnboarding = true
                        NSApplication.shared.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)

            Text("Welcome to Wisper")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Speech to text that runs entirely on your Mac.\nPrivate, fast, and always available.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Permissions")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture your voice",
                    action: {
                        Task { _ = await AudioEngine.requestPermission() }
                    }
                )

                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Required to type text into other apps",
                    action: {
                        appState.textInjector?.requestAccessibility()
                    }
                )
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private func permissionRow(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Grant") {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Model Download

    private var modelStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Download Model")
                .font(.title)
                .fontWeight(.bold)

            Text("Wisper uses the Whisper AI model which runs locally on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(AppState.availableModels, id: \.id) { model in
                        Text("\(model.name) (\(model.size))").tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Language", selection: $appState.selectedLanguage) {
                    ForEach(AppState.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)

                switch appState.modelPhase {
                case .downloading(let progress):
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                        Text(String(format: "Downloading... %.1f%%", progress * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .loading(let step):
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(step)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                case .ready:
                    Label("Model ready!", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)

                case .error(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)

                    Button("Retry Download") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                case .idle:
                    Button("Download Model") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
