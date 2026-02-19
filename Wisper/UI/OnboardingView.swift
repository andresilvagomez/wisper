import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                permissionsStep.tag(1)
                modelStep.tag(2)
            }
            .tabViewStyle(.automatic)

            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .task {
            appState.refreshPermissionState()
            if appState.hasCompletedOnboarding {
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.title == "Wisper Setup" }?.close()
                }
            }
        }
    }

    private var onboardingMachine: OnboardingStateMachine {
        OnboardingStateMachine(
            currentStep: OnboardingStep(rawValue: currentStep) ?? .welcome,
            needsAccessibility: appState.needsAccessibility,
            needsMicrophone: appState.needsMicrophone,
            modelIsReady: appState.modelPhase.isReady,
            modelIsLoading: appState.modelPhase.isActive
        )
    }

    private var shortcutAdvisory: ShortcutAdvisory {
        ShortcutConflictEvaluator.advisory(for: KeyboardShortcuts.getShortcut(for: HotkeyManager.shortcutName))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configuración de Wisper")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("Paso \(currentStep + 1) de 3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 6)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if currentStep > 0 {
                Button("Atrás") {
                    var machine = onboardingMachine
                    machine.goBack()
                    withAnimation { currentStep = machine.currentStep.rawValue }
                }
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            switch currentStep {
            case 0:
                Button("Continuar") {
                    var machine = onboardingMachine
                    machine.goToNextPrimaryStep()
                    withAnimation { currentStep = machine.currentStep.rawValue }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case 1:
                HStack(spacing: 10) {
                    if !onboardingMachine.canContinueFromPermissions {
                        Button("Continuar de todas formas") {
                            var machine = onboardingMachine
                            machine.goToNextPrimaryStep()
                            withAnimation { currentStep = machine.currentStep.rawValue }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(onboardingMachine.canContinueFromPermissions ? "Continuar" : "Continuar con permisos")
                    {
                        var machine = onboardingMachine
                        machine.goToNextPrimaryStep()
                        withAnimation { currentStep = machine.currentStep.rawValue }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            default:
                if onboardingMachine.canFinishOnboarding {
                    HStack(spacing: 10) {
                        if onboardingMachine.canStartTest {
                            Button("Probar ahora") {
                                appState.hasCompletedOnboarding = true
                                NSApplication.shared.keyWindow?.close()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    appState.startRecording()
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Empezar a usar Wisper") {
                            appState.hasCompletedOnboarding = true
                            NSApplication.shared.keyWindow?.close()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("Cargar modelo") {
                        Task { await appState.loadModel() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!onboardingMachine.canLoadModel)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Step 1

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)

            Text("Dictado local, rápido y privado")
                .font(.title)
                .fontWeight(.bold)

            Text("Wisper transcribe en tu Mac con Whisper.\nSin enviar audio a la nube.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "mic.fill", text: "Graba con un atajo global")
                featureRow(icon: "bolt.fill", text: "Inserta texto donde tengas el cursor")
                featureRow(icon: "lock.fill", text: "Procesamiento on-device")
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 8)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.body)
            Spacer()
        }
    }

    // MARK: - Step 2

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permisos necesarios")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Para grabar y pegar texto en otras apps, Wisper necesita estos permisos.")
                .foregroundColor(.secondary)

            permissionCard(
                icon: "mic.fill",
                title: "Micrófono",
                granted: !appState.needsMicrophone,
                buttonTitle: appState.needsMicrophone ? "Conceder acceso" : "Concedido",
                buttonAction: {
                    Task { await appState.requestMicrophonePermission() }
                },
                helpMessage: microphoneHelpText
            )

            permissionCard(
                icon: "hand.raised.fill",
                title: "Accesibilidad",
                granted: !appState.needsAccessibility,
                buttonTitle: appState.needsAccessibility ? "Abrir ajuste" : "Concedido",
                buttonAction: {
                    appState.refreshPermissionState(requestAccessibilityPrompt: true)
                },
                helpMessage: accessibilityHelpText
            )

            HStack(spacing: 10) {
                Button("Verificar de nuevo") {
                    appState.refreshPermissionState()
                }
                .buttonStyle(.bordered)

                if onboardingMachine.canContinueFromPermissions {
                    Label("Todo listo", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.callout)
                } else {
                    Text("Puedes continuar y reintentar luego sin bloquear la app")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    private func permissionCard(
        icon: String,
        title: String,
        granted: Bool,
        buttonTitle: String,
        buttonAction: @escaping () -> Void,
        helpMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(granted ? .green : .orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(granted ? "Permiso activo" : "Permiso pendiente")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.bordered)
                    .disabled(granted)
            }

            if !granted {
                Text(helpMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step 3

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Atajo y modelo")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Define tu atajo y deja el modelo listo para usar.")
                .foregroundColor(.secondary)

            GroupBox("Atajo global") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        KeyboardShortcuts.Recorder("Grabar", name: HotkeyManager.shortcutName)
                        Spacer()
                    }

                    shortcutAdvisoryView
                }
                .padding(.top, 2)
            }

            GroupBox("Modelo de transcripción") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Modelo", selection: $appState.selectedModel) {
                        ForEach(AppState.availableModels, id: \.id) { model in
                            Text("\(model.name) (\(model.size))").tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(appState.modelPhase.isActive)

                    Picker("Idioma", selection: $appState.selectedLanguage) {
                        ForEach(AppState.availableLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(appState.modelPhase.isActive)

                    modelStatusView
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var modelStatusView: some View {
        switch appState.modelPhase {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                Text(String(format: "Descargando… %.0f%%", progress * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .loading(let step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(step)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .ready:
            Label("Modelo listo para transcribir", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.callout)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .idle:
            Text("Pulsa “Cargar modelo” para finalizar.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var microphoneHelpText: String {
        switch appState.microphonePermissionStatus {
        case .authorized:
            return "Micrófono listo."
        case .notDetermined:
            return "Pulsa “Conceder acceso” y acepta el diálogo de macOS."
        case .denied, .restricted:
            return "Abre Ajustes del Sistema > Privacidad y Seguridad > Micrófono y habilita Wisper."
        @unknown default:
            return "Verifica el permiso en Ajustes del Sistema."
        }
    }

    private var accessibilityHelpText: String {
        if appState.needsAccessibility {
            return "Abre Ajustes del Sistema > Privacidad y Seguridad > Accesibilidad y activa Wisper. Luego usa “Verificar de nuevo”."
        }
        return "Accesibilidad lista."
    }

    @ViewBuilder
    private var shortcutAdvisoryView: some View {
        let advisory = shortcutAdvisory
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: advisoryIcon(for: advisory.level))
                .foregroundColor(advisoryColor(for: advisory.level))
            VStack(alignment: .leading, spacing: 2) {
                Text(advisory.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(advisory.message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func advisoryIcon(for level: ShortcutAdvisoryLevel) -> String {
        switch level {
        case .info:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }

    private func advisoryColor(for level: ShortcutAdvisoryLevel) -> Color {
        switch level {
        case .info:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}
