import KeyboardShortcuts

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case setup = 2
}

struct OnboardingStateMachine {
    var currentStep: OnboardingStep
    var needsAccessibility: Bool
    var needsMicrophone: Bool
    var modelIsReady: Bool
    var modelIsLoading: Bool

    var canContinueFromPermissions: Bool {
        !needsAccessibility && !needsMicrophone
    }

    var canStartTest: Bool {
        currentStep == .setup && modelIsReady && canContinueFromPermissions
    }

    var canFinishOnboarding: Bool {
        currentStep == .setup && modelIsReady
    }

    var canLoadModel: Bool {
        currentStep == .setup && !modelIsLoading
    }

    mutating func goBack() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    mutating func goToNextPrimaryStep() {
        switch currentStep {
        case .welcome:
            currentStep = .permissions
        case .permissions:
            currentStep = .setup
        case .setup:
            break
        }
    }
}

enum ShortcutAdvisoryLevel: Equatable {
    case info
    case warning
    case critical
}

struct ShortcutAdvisory {
    let level: ShortcutAdvisoryLevel
    let title: String
    let message: String
}

enum ShortcutConflictEvaluator {
    static func advisory(for shortcut: KeyboardShortcuts.Shortcut?) -> ShortcutAdvisory {
        guard let shortcut else {
            return ShortcutAdvisory(
                level: .warning,
                title: "Define un atajo",
                message: "Selecciona una combinación para grabar sin abrir la configuración."
            )
        }

        let modifiers = shortcut.modifiers
        let key = shortcut.key

        if modifiers.isEmpty {
            return ShortcutAdvisory(
                level: .critical,
                title: "Atajo inválido",
                message: "Incluye al menos una tecla modificadora (⌘, ⌥, ⌃ o ⇧)."
            )
        }

        if modifiers == [.command], key == .space {
            return ShortcutAdvisory(
                level: .critical,
                title: "Conflicto fuerte detectado",
                message: "⌘Space suele abrir Spotlight. Elige otro atajo para evitar bloqueos."
            )
        }

        if modifiers == [.command], key == .tab {
            return ShortcutAdvisory(
                level: .critical,
                title: "Conflicto fuerte detectado",
                message: "⌘Tab cambia de aplicación y puede impedir la grabación."
            )
        }

        if modifiers == [.control], key == .space {
            return ShortcutAdvisory(
                level: .warning,
                title: "Posible conflicto",
                message: "⌃Space suele cambiar idioma de teclado en macOS."
            )
        }

        if modifiers.contains(.command), key == .q {
            return ShortcutAdvisory(
                level: .warning,
                title: "Posible conflicto",
                message: "Combinar ⌘ con Q puede cerrar apps accidentalmente."
            )
        }

        return ShortcutAdvisory(
            level: .info,
            title: "Atajo recomendado",
            message: "Si no funciona en una app específica, cambia a una combinación menos común."
        )
    }
}
