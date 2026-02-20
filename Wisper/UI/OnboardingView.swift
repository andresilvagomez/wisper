import KeyboardShortcuts
import SwiftUI
import Combine

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    private let permissionsAutoRefresh = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

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
            if appState.needsAccessibility || appState.needsMicrophone {
                currentStep = 1
            }
            if appState.hasCompletedOnboarding {
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.title == L10n.t("window.onboarding.title") }?.close()
                }
            }
        }
        .onReceive(permissionsAutoRefresh) { _ in
            guard currentStep == 1 else { return }
            appState.refreshPermissionState()
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
                Text(L10n.f("onboarding.header.step_of", currentStep + 1, 3))
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
                Button("Continuar") {
                    var machine = onboardingMachine
                    machine.goToNextPrimaryStep()
                    withAnimation { currentStep = machine.currentStep.rawValue }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!onboardingMachine.canContinueFromPermissions)
                .keyboardShortcut(.defaultAction)
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

            Text("Activa estos permisos para usar Wisper con una experiencia completa.")
                .foregroundColor(.secondary)

            if appState.needsMicrophone || appState.needsAccessibility {
                Label("Activa ambos permisos para usar Wisper sin bloqueos.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundColor(.orange)
            }

            permissionCard(
                icon: "mic.fill",
                title: "Micrófono",
                granted: !appState.needsMicrophone,
                buttonTitle: appState.needsMicrophone ? "Conceder acceso" : "Concedido",
                buttonAction: {
                    Task { await requestMicrophoneFlow() }
                },
                helpMessage: microphoneHelpText
            )

            permissionCard(
                icon: "hand.raised.fill",
                title: "Accesibilidad",
                granted: !appState.needsAccessibility,
                buttonTitle: appState.needsAccessibility ? "Abrir ajuste" : "Concedido",
                buttonAction: {
                    requestAccessibilityFlow()
                },
                helpMessage: accessibilityHelpText
            )

            premiumPermissionsGuide

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
                    Text("Esta pantalla se mantendrá hasta que ambos permisos estén activos.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    private var premiumPermissionsGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guía rápida")
                .font(.subheadline)
                .fontWeight(.semibold)

            guidedStep(
                number: 1,
                title: "Activa Micrófono",
                done: !appState.needsMicrophone,
                actionTitle: "Abrir ajuste",
                action: { appState.openSystemSettings(.microphone) }
            )

            guidedStep(
                number: 2,
                title: "Activa Accesibilidad",
                done: !appState.needsAccessibility,
                actionTitle: "Abrir ajuste",
                action: { appState.openSystemSettings(.accessibility) }
            )

            guidedStep(
                number: 3,
                title: "Vuelve a Wisper",
                done: onboardingMachine.canContinueFromPermissions,
                actionTitle: "Verificar ahora",
                action: { appState.refreshPermissionState() }
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func guidedStep(
        number: Int,
        title: String,
        done: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }
            }

            Text(title)
                .font(.callout)

            Spacer()

            Button(done ? "Listo" : actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(done)
        }
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
                    Label(L10n.t("onboarding.model.default_included"), systemImage: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.callout)

                    Text(L10n.t("onboarding.model.super_pro_note"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                Text(L10n.f("onboarding.model.downloading_percent", progress * 100))
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
            return L10n.t("onboarding.permissions.microphone.ready")
        case .notDetermined:
            return L10n.t("onboarding.permissions.microphone.not_determined")
        case .denied, .restricted:
            return L10n.t("onboarding.permissions.microphone.denied")
        @unknown default:
            return L10n.t("onboarding.permissions.microphone.unknown")
        }
    }

    private var accessibilityHelpText: String {
        if appState.needsAccessibility {
            return L10n.t("onboarding.permissions.accessibility.pending")
        }
        return L10n.t("onboarding.permissions.accessibility.ready")
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

    private func requestAccessibilityFlow() {
        appState.refreshPermissionState(requestAccessibilityPrompt: true)
        if appState.needsAccessibility {
            appState.openSystemSettings(.accessibility)
        }
    }

    private func requestMicrophoneFlow() async {
        await appState.requestMicrophonePermission()
        if appState.needsMicrophone {
            appState.openSystemSettings(.microphone)
        }
    }
}
