import KeyboardShortcuts

enum OnboardingStep: Int, CaseIterable {
    case permissions = 0
    case setup = 1
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
                title: L10n.t("shortcut_advisory.define_shortcut.title"),
                message: L10n.t("shortcut_advisory.define_shortcut.message")
            )
        }

        let modifiers = shortcut.modifiers
        let key = shortcut.key

        if modifiers.isEmpty {
            return ShortcutAdvisory(
                level: .critical,
                title: L10n.t("shortcut_advisory.invalid.title"),
                message: L10n.t("shortcut_advisory.invalid.message")
            )
        }

        if modifiers == [.command], key == .space {
            return ShortcutAdvisory(
                level: .critical,
                title: L10n.t("shortcut_advisory.strong_conflict.title"),
                message: L10n.t("shortcut_advisory.spotlight.message")
            )
        }

        if modifiers == [.command], key == .tab {
            return ShortcutAdvisory(
                level: .critical,
                title: L10n.t("shortcut_advisory.strong_conflict.title"),
                message: L10n.t("shortcut_advisory.cmd_tab.message")
            )
        }

        if modifiers == [.control], key == .space {
            return ShortcutAdvisory(
                level: .warning,
                title: L10n.t("shortcut_advisory.possible_conflict.title"),
                message: L10n.t("shortcut_advisory.ctrl_space.message")
            )
        }

        if modifiers.contains(.command), key == .q {
            return ShortcutAdvisory(
                level: .warning,
                title: L10n.t("shortcut_advisory.possible_conflict.title"),
                message: L10n.t("shortcut_advisory.cmd_q.message")
            )
        }

        return ShortcutAdvisory(
            level: .info,
            title: L10n.t("shortcut_advisory.recommended.title"),
            message: L10n.t("shortcut_advisory.recommended.message")
        )
    }
}
