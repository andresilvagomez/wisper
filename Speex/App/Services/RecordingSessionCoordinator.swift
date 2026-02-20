import Foundation

enum RecordingStartEvaluation: Equatable {
    case alreadyRecording
    case deferredByModel
    case blockedMicrophone
    case blockedAccessibility
    case readyToStart
}

struct RecordingCaptureSettings: Equatable {
    let inputGain: Float
    let noiseGate: Float
}

enum RecordingStopEvaluation: Equatable {
    case notRecording
    case stopped(shouldFinalizeOnRelease: Bool)
}

@MainActor
final class RecordingSessionCoordinator {
    private(set) var recordingStartedAt: Date?

    func evaluateStart(
        isRecording: Bool,
        deferredByModel: Bool,
        needsMicrophone: Bool,
        needsAccessibility: Bool
    ) -> RecordingStartEvaluation {
        if isRecording { return .alreadyRecording }
        if deferredByModel { return .deferredByModel }
        if needsMicrophone { return .blockedMicrophone }
        if needsAccessibility { return .blockedAccessibility }
        return .readyToStart
    }

    func beginSession(now: Date = .now) {
        recordingStartedAt = now
    }

    func resetSessionState() {
        recordingStartedAt = nil
    }

    func stopSession(
        isRecording: Bool,
        transcriptionMode: TranscriptionMode
    ) -> RecordingStopEvaluation {
        guard isRecording else { return .notRecording }
        recordingStartedAt = nil
        return .stopped(shouldFinalizeOnRelease: transcriptionMode == .onRelease)
    }

    func captureSettings(whisperModeEnabled: Bool) -> RecordingCaptureSettings {
        if whisperModeEnabled {
            return RecordingCaptureSettings(inputGain: 2.2, noiseGate: 0.004)
        }
        return RecordingCaptureSettings(inputGain: 1.0, noiseGate: 0)
    }
}
