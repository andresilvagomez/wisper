import Testing
@testable import Speex

@Suite("Recording Orchestrator")
@MainActor
struct RecordingOrchestratorTests {

    // MARK: - Initialization

    @Test("Initial recordingStartedAt is nil")
    func initialRecordingStartedAtNil() {
        let orchestrator = RecordingOrchestrator()
        #expect(orchestrator.recordingStartedAt == nil)
    }

    @Test("AppState is nil by default")
    func appStateNilByDefault() {
        let orchestrator = RecordingOrchestrator()
        #expect(orchestrator.appState == nil)
    }

    @Test("Sub-coordinators are initialized")
    func subCoordinatorsInitialized() {
        let orchestrator = RecordingOrchestrator()
        // Verify transcriptionCoordinator works by calling resetSession
        let result = orchestrator.transcriptionCoordinator.resetSession()
        #expect(result.confirmedText == "")
        #expect(result.partialText == "")
    }

    // MARK: - No-op Without AppState

    @Test("startRecording is no-op without appState")
    func startRecordingNoOpWithoutAppState() {
        let orchestrator = RecordingOrchestrator()
        // Should not crash
        orchestrator.startRecording()
        #expect(orchestrator.recordingStartedAt == nil)
    }

    @Test("stopRecording is no-op without appState")
    func stopRecordingNoOpWithoutAppState() {
        let orchestrator = RecordingOrchestrator()
        orchestrator.stopRecording()
    }

    @Test("cleanup runs forceUnmute even without appState")
    func cleanupRunsForceUnmuteWithoutAppState() {
        let orchestrator = RecordingOrchestrator()
        // Should not crash — forceUnmute runs before the appState guard
        orchestrator.cleanup()
    }

    // MARK: - Session Coordinator Delegation

    @Test("Session coordinator evaluates start correctly")
    func sessionCoordinatorEvaluateStart() {
        let orchestrator = RecordingOrchestrator()
        let result = orchestrator.sessionCoordinator.evaluateStart(
            isRecording: false,
            deferredByModel: false,
            needsMicrophone: false,
            needsAccessibility: false
        )
        #expect(result == .readyToStart)
    }

    @Test("Session coordinator blocks when already recording")
    func sessionCoordinatorBlocksWhenRecording() {
        let orchestrator = RecordingOrchestrator()
        let result = orchestrator.sessionCoordinator.evaluateStart(
            isRecording: true,
            deferredByModel: false,
            needsMicrophone: false,
            needsAccessibility: false
        )
        #expect(result == .alreadyRecording)
    }

    @Test("Session coordinator blocks when microphone missing")
    func sessionCoordinatorBlocksMicrophone() {
        let orchestrator = RecordingOrchestrator()
        let result = orchestrator.sessionCoordinator.evaluateStart(
            isRecording: false,
            deferredByModel: false,
            needsMicrophone: true,
            needsAccessibility: false
        )
        #expect(result == .blockedMicrophone)
    }

    @Test("Session coordinator blocks when accessibility missing")
    func sessionCoordinatorBlocksAccessibility() {
        let orchestrator = RecordingOrchestrator()
        let result = orchestrator.sessionCoordinator.evaluateStart(
            isRecording: false,
            deferredByModel: false,
            needsMicrophone: false,
            needsAccessibility: true
        )
        #expect(result == .blockedAccessibility)
    }

    // MARK: - Transcription Coordinator

    @Test("Transcription coordinator consumePartial returns expected state")
    func transcriptionCoordinatorPartial() {
        let orchestrator = RecordingOrchestrator()
        _ = orchestrator.transcriptionCoordinator.resetSession()

        let result = orchestrator.transcriptionCoordinator.consumePartial(
            "Hello",
            confirmedText: ""
        )
        #expect(result.partialText == "Hello")
    }

    // MARK: - Streaming vs On-Release Stop Evaluation

    @Test("Session stop in streaming mode returns shouldFinalizeOnRelease false")
    func stopSessionStreamingMode() {
        let orchestrator = RecordingOrchestrator()
        orchestrator.sessionCoordinator.beginSession()

        let evaluation = orchestrator.sessionCoordinator.stopSession(
            isRecording: true,
            transcriptionMode: .streaming
        )

        switch evaluation {
        case let .stopped(shouldFinalizeOnRelease):
            #expect(shouldFinalizeOnRelease == false,
                    "Streaming mode should NOT finalize on release")
        case .notRecording:
            Issue.record("Expected .stopped but got .notRecording")
        }
    }

    @Test("Session stop in onRelease mode returns shouldFinalizeOnRelease true")
    func stopSessionOnReleaseMode() {
        let orchestrator = RecordingOrchestrator()
        orchestrator.sessionCoordinator.beginSession()

        let evaluation = orchestrator.sessionCoordinator.stopSession(
            isRecording: true,
            transcriptionMode: .onRelease
        )

        switch evaluation {
        case let .stopped(shouldFinalizeOnRelease):
            #expect(shouldFinalizeOnRelease == true,
                    "On-release mode should finalize on release")
        case .notRecording:
            Issue.record("Expected .stopped but got .notRecording")
        }
    }

    @Test("Session stop when not recording returns notRecording")
    func stopSessionNotRecording() {
        let orchestrator = RecordingOrchestrator()
        let evaluation = orchestrator.sessionCoordinator.stopSession(
            isRecording: false,
            transcriptionMode: .streaming
        )
        #expect(evaluation == .notRecording)
    }

    // MARK: - System Audio Muter

    @Test("System audio muter is accessible and functional")
    func systemAudioMuterAccessible() {
        let orchestrator = RecordingOrchestrator()
        // Should not crash
        orchestrator.systemAudioMuter.forceUnmute()
    }
}
