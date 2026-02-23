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
                permissionsStep.tag(0)
                modelStep.tag(1)
            }
            .tabViewStyle(.automatic)

            Divider()
            footer
        }
        .frame(width: 760, height: 520)
        .task {
            appState.refreshPermissionState()
            if appState.hasCompletedOnboarding {
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.title == L10n.t("window.onboarding.title") }?.close()
                }
            } else if !appState.needsAccessibility && !appState.needsMicrophone {
                currentStep = 1
            }
        }
        .onReceive(permissionsAutoRefresh) { _ in
            guard currentStep == 0,
                  appState.needsAccessibility || appState.needsMicrophone
            else { return }
            appState.refreshPermissionState()
        }
    }

    private var onboardingMachine: OnboardingStateMachine {
        OnboardingStateMachine(
            currentStep: OnboardingStep(rawValue: currentStep) ?? .permissions,
            needsAccessibility: appState.needsAccessibility,
            needsMicrophone: appState.needsMicrophone,
            modelIsReady: appState.modelPhase.isReady,
            modelIsLoading: appState.modelPhase.isActive
        )
    }

    private var shortcutAdvisory: ShortcutAdvisory {
        ShortcutConflictEvaluator.advisory(for: KeyboardShortcuts.getShortcut(for: HotkeyManager.shortcutName))
    }

    private var modelActionButtonTitle: String {
        switch appState.modelPhase {
        case .downloading:
            return "Descargando..."
        case .loading:
            return "Preparando..."
        case .idle, .error:
            if appState.isModelInstalledLocally(appState.selectedModel) {
                return "Instalar modelo"
            }
            return "Descargar e instalar"
        case .ready:
            return "Instalar modelo"
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
                Text("Configuración de Speex")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text(L10n.f("onboarding.header.step_of", currentStep + 1, 2))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.primary : Color.secondary.opacity(0.25))
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

                        Button("Empezar a usar Speex") {
                            appState.hasCompletedOnboarding = true
                            NSApplication.shared.keyWindow?.close()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button(modelActionButtonTitle) {
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

    // MARK: - Step 1: Permissions (split layout)

    private var permissionsStep: some View {
        HStack(spacing: 0) {
            // Left side: permission cards
            permissionsLeftPanel
                .frame(maxWidth: .infinity)

            Divider()

            // Right side: visual guide
            permissionsRightPanel
                .frame(width: 310)
        }
    }

    private var permissionsLeftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permisos necesarios")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Speex necesita estos permisos para transcribir y pegar texto.")
                .foregroundColor(.secondary)
                .font(.callout)

            permissionCard(
                icon: "mic.fill",
                title: "Micrófono",
                description: "Para capturar tu voz",
                granted: !appState.needsMicrophone,
                buttonTitle: appState.needsMicrophone ? "Conceder acceso" : "Concedido",
                buttonAction: {
                    Task { await requestMicrophoneFlow() }
                }
            )

            permissionCard(
                icon: "hand.raised.fill",
                title: "Accesibilidad",
                description: "Para insertar texto donde tengas el cursor",
                granted: !appState.needsAccessibility,
                buttonTitle: appState.needsAccessibility ? "Abrir ajuste" : "Concedido",
                buttonAction: {
                    requestAccessibilityFlow()
                }
            )

            if onboardingMachine.canContinueFromPermissions {
                Label("Todo listo — pulsa Continuar", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.callout)
            } else {
                Button("Verificar de nuevo") {
                    appState.refreshPermissionState()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(24)
    }

    private var permissionsRightPanel: some View {
        VStack(spacing: 16) {
            Spacer()

            if onboardingMachine.canContinueFromPermissions {
                // All permissions granted — show success
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green.gradient)
                    Text("Permisos activos")
                        .font(.headline)
                    Text("Speex tiene todo lo que necesita.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Show the visual guide for the pending permission
                systemSettingsGuide
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    /// Determines which permission to focus on in the visual guide.
    private var focusedPermissionIsMicrophone: Bool {
        appState.needsMicrophone
    }

    // MARK: - System Settings Visual Guide

    private var systemSettingsGuide: some View {
        VStack(spacing: 12) {
            Text("Cómo activarlo")
                .font(.headline)

            // Mock System Settings window
            VStack(spacing: 0) {
                // Title bar
                HStack(spacing: 6) {
                    Circle().fill(Color.red.opacity(0.8)).frame(width: 10, height: 10)
                    Circle().fill(Color.orange.opacity(0.8)).frame(width: 10, height: 10)
                    Circle().fill(Color.green.opacity(0.8)).frame(width: 10, height: 10)
                    Spacer()
                    Text("Ajustes del Sistema")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Color.clear.frame(width: 36, height: 10)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Breadcrumb
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9))
                    Text("Privacidad y seguridad")
                        .font(.system(size: 10))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7))
                    Text(focusedPermissionIsMicrophone ? "Micrófono" : "Accesibilidad")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(focusedPermissionIsMicrophone
                         ? "Permitir que las apps accedan al micrófono:"
                         : "Permitir que las apps controlen tu ordenador:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Dimmed example app
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 20, height: 20)
                        Text("Otra app")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .opacity(0.3)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    // Speex row — highlighted
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                        Text("Speex")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.4), lineWidth: 1.5)
                    )
                }
                .padding(12)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

            // Instruction below the mock
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.primary)
                Text("Activa el interruptor de Speex")
                    .font(.callout)
                    .foregroundColor(.primary)
            }

            Button(focusedPermissionIsMicrophone ? "Abrir en Ajustes" : "Abrir en Ajustes") {
                if focusedPermissionIsMicrophone {
                    Task { await requestMicrophoneFlow() }
                } else {
                    requestAccessibilityFlow()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        buttonTitle: String,
        buttonAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(granted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? Color.green.opacity(0.06) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(granted ? Color.green.opacity(0.2) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Step 2: Model Selection

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Elige tu motor de transcripción")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Selecciona cómo quieres procesar tu voz.")
                .foregroundColor(.secondary)
                .font(.callout)

            HStack(spacing: 12) {
                modelOptionCard(
                    icon: "bolt.fill",
                    title: "Speex Turbo",
                    badge: "Recomendado",
                    badgeColor: .primary,
                    features: ["Rápido y muy preciso", "Funciona sin conexión", "Descarga ligera (~632 MB)"],
                    isSelected: appState.selectedModel == AppState.defaultBundledModelID,
                    isDisabled: appState.modelPhase.isActive,
                    isInstalled: appState.isModelInstalledLocally(AppState.defaultBundledModelID)
                ) {
                    appState.selectedModel = AppState.defaultBundledModelID
                }

                modelOptionCard(
                    icon: "sparkles",
                    title: "Speex Super Pro",
                    badge: "Máxima precisión",
                    badgeColor: .purple,
                    features: ["Máxima precisión por palabra", "Funciona sin conexión", "Para dictados extensos (~1.5 GB)"],
                    isSelected: appState.selectedModel == AppState.optionalSuperModelID,
                    isDisabled: appState.modelPhase.isActive,
                    isInstalled: appState.isModelInstalledLocally(AppState.optionalSuperModelID)
                ) {
                    appState.selectedModel = AppState.optionalSuperModelID
                }

                modelOptionCard(
                    icon: "cloud.fill",
                    title: "Cloud",
                    badge: "Próximamente",
                    badgeColor: .gray,
                    features: ["Sin usar espacio en tu Mac", "Siempre actualizado", "Disponible próximamente"],
                    isSelected: false,
                    isDisabled: true,
                    isInstalled: false
                ) { }
            }

            modelStatusView

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Picker("Idioma", selection: $appState.selectedLanguage) {
                        ForEach(AppState.availableLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(appState.modelPhase.isActive)
                }

                Divider().frame(height: 20)

                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    KeyboardShortcuts.Recorder("Atajo", name: HotkeyManager.shortcutName)
                }

                Spacer()
            }

            if shortcutAdvisory.level != .info {
                shortcutAdvisoryView
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func modelOptionCard(
        icon: String,
        title: String,
        badge: String,
        badgeColor: Color,
        features: [String],
        isSelected: Bool,
        isDisabled: Bool,
        isInstalled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isDisabled ? Color.gray.gradient : badgeColor.gradient)
                    Spacer()
                    if isInstalled {
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

    @ViewBuilder
    private var modelStatusView: some View {
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
                Text(L10n.f("onboarding.model.downloading_percent", progress * 100))
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
            Label("Modelo listo para transcribir", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.callout)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .idle:
            if appState.isModelInstalledLocally(appState.selectedModel) {
                Label("Modelo descargado — listo para instalar", systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.primary)
                    .font(.callout)
            } else {
                Label("Se descargará al instalar", systemImage: "arrow.down.to.line")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
        }
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
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private func advisoryColor(for level: ShortcutAdvisoryLevel) -> Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        case .critical: return .red
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
