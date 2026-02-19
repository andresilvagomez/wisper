import KeyboardShortcuts
import Testing
@testable import Wisper

@Suite("Onboarding State Machine")
struct OnboardingStateMachineTests {
    @Test("Primary flow advances welcome to permissions to setup")
    func primaryFlowAdvance() {
        var machine = OnboardingStateMachine(
            currentStep: .welcome,
            needsAccessibility: true,
            needsMicrophone: true,
            modelIsReady: false,
            modelIsLoading: false
        )

        machine.goToNextPrimaryStep()
        #expect(machine.currentStep == .permissions)

        machine.goToNextPrimaryStep()
        #expect(machine.currentStep == .setup)
    }

    @Test("Back navigation does not go below welcome")
    func backNavigationBounds() {
        var machine = OnboardingStateMachine(
            currentStep: .welcome,
            needsAccessibility: false,
            needsMicrophone: false,
            modelIsReady: false,
            modelIsLoading: false
        )

        machine.goBack()
        #expect(machine.currentStep == .welcome)
    }

    @Test("Permission gate and completion states")
    func permissionAndCompletionGates() {
        let blockedMachine = OnboardingStateMachine(
            currentStep: .setup,
            needsAccessibility: true,
            needsMicrophone: false,
            modelIsReady: true,
            modelIsLoading: false
        )
        #expect(!blockedMachine.canContinueFromPermissions)
        #expect(!blockedMachine.canStartTest)
        #expect(blockedMachine.canFinishOnboarding)

        let readyMachine = OnboardingStateMachine(
            currentStep: .setup,
            needsAccessibility: false,
            needsMicrophone: false,
            modelIsReady: true,
            modelIsLoading: false
        )
        #expect(readyMachine.canContinueFromPermissions)
        #expect(readyMachine.canStartTest)
        #expect(readyMachine.canFinishOnboarding)
    }

    @Test("Load model action is blocked while loading")
    func loadModelGate() {
        let loadingMachine = OnboardingStateMachine(
            currentStep: .setup,
            needsAccessibility: false,
            needsMicrophone: false,
            modelIsReady: false,
            modelIsLoading: true
        )
        #expect(!loadingMachine.canLoadModel)
    }
}

@Suite("Shortcut Conflict Evaluator")
struct ShortcutConflictEvaluatorTests {
    @Test("Detects critical Spotlight conflict")
    func detectsSpotlightConflict() {
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command])
        let advisory = ShortcutConflictEvaluator.advisory(for: shortcut)
        #expect(advisory.level == .critical)
    }

    @Test("Detects warning input-source conflict")
    func detectsInputSourceConflict() {
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])
        let advisory = ShortcutConflictEvaluator.advisory(for: shortcut)
        #expect(advisory.level == .warning)
    }

    @Test("Provides info for default Option+Space")
    func validatesDefaultShortcut() {
        let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
        let advisory = ShortcutConflictEvaluator.advisory(for: shortcut)
        #expect(advisory.level == .info)
    }
}
