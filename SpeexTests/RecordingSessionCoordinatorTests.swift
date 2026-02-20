import Foundation
import Testing
@testable import Speex

@Suite("Recording Session Coordinator")
@MainActor
struct RecordingSessionCoordinatorTests {
    @Test("Start evaluation blocks already-recording state")
    func startAlreadyRecording() {
        let coordinator = RecordingSessionCoordinator()
        let result = coordinator.evaluateStart(
            isRecording: true,
            deferredByModel: false,
            needsMicrophone: false,
            needsAccessibility: false
        )
        #expect(result == .alreadyRecording)
    }

    @Test("Start evaluation prioritizes model defer before permissions")
    func startDeferredByModel() {
        let coordinator = RecordingSessionCoordinator()
        let result = coordinator.evaluateStart(
            isRecording: false,
            deferredByModel: true,
            needsMicrophone: true,
            needsAccessibility: true
        )
        #expect(result == .deferredByModel)
    }

    @Test("Start evaluation blocks missing microphone")
    func startBlockedByMicrophone() {
        let coordinator = RecordingSessionCoordinator()
        let result = coordinator.evaluateStart(
            isRecording: false,
            deferredByModel: false,
            needsMicrophone: true,
            needsAccessibility: false
        )
        #expect(result == .blockedMicrophone)
    }

    @Test("Capture settings adapt to whisper mode")
    func captureSettings() {
        let coordinator = RecordingSessionCoordinator()
        let whisperOn = coordinator.captureSettings(whisperModeEnabled: true)
        let whisperOff = coordinator.captureSettings(whisperModeEnabled: false)

        #expect(whisperOn == RecordingCaptureSettings(inputGain: 2.2, noiseGate: 0.004))
        #expect(whisperOff == RecordingCaptureSettings(inputGain: 1.0, noiseGate: 0))
    }

    @Test("Session lifecycle sets and clears start timestamp")
    func sessionLifecycle() {
        let coordinator = RecordingSessionCoordinator()
        let startDate = Date(timeIntervalSince1970: 123)
        coordinator.beginSession(now: startDate)
        #expect(coordinator.recordingStartedAt == startDate)

        let stop = coordinator.stopSession(isRecording: true, transcriptionMode: .streaming)
        #expect(stop == .stopped(shouldFinalizeOnRelease: false))
        #expect(coordinator.recordingStartedAt == nil)
    }
}
