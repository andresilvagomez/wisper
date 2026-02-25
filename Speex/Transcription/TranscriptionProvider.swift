import Foundation

/// Contract for transcription engines.
///
/// Both local (WhisperKit) and cloud (OpenAI) engines conform to this protocol,
/// allowing AppState to switch implementations transparently.
protocol TranscriptionProvider: AnyObject, Sendable {

    /// Feed raw PCM audio (16 kHz mono Float32) into the engine.
    func processAudioBuffer(_ samples: [Float])

    /// Reset all session state (buffers, context tokens, language lock).
    func resetSession()

    /// Prevent new chunk processing so remaining audio flows to `finalize()`.
    func prepareForFinalize()

    /// Wait for any in-flight chunk transcription to complete.
    func flushProcessing() async

    /// Re-transcribe the tail of the session audio and extract the delta.
    func finalize(
        confirmedText: String,
        completion: (@Sendable (_ finalText: String?) -> Void)?
    )

    /// Clear the audio accumulator.
    func clearBuffer()

    /// Prepare the engine for transcription.
    ///
    /// For local engines this downloads/loads the model.
    /// For cloud engines this validates the API key.
    func loadModel(
        modelName: String,
        language: String?,
        onPhaseChange: @escaping @Sendable (ModelPhase) -> Void,
        eagerWarmup: Bool
    ) async -> Bool
}
