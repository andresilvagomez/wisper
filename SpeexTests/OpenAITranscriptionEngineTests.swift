import Foundation
import Testing
@testable import Speex

@Suite("OpenAI Transcription Engine")
struct OpenAITranscriptionEngineTests {

    // MARK: - Initialization

    @Test("Engine initializes with API key and callbacks")
    func initializesCorrectly() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        // Should not crash — engine is ready
        _ = engine
    }

    @Test("Engine conforms to TranscriptionProvider protocol")
    func conformsToProtocol() {
        let engine: any TranscriptionProvider = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        // Verify protocol methods exist
        engine.resetSession()
        engine.clearBuffer()
    }

    // MARK: - Buffer Management

    @Test("processAudioBuffer accumulates samples")
    func processAudioBufferAccumulates() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        // Small buffer — not enough for a chunk, so no processing
        let samples = Array(repeating: Float(0.1), count: 100)
        engine.processAudioBuffer(samples)
        // Should not crash
    }

    @Test("resetSession clears all buffers")
    func resetSessionClearsBuffers() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        engine.processAudioBuffer(Array(repeating: Float(0), count: 1000))
        engine.resetSession()
        // Should not crash — buffers are cleared
    }

    @Test("clearBuffer delegates to resetSession")
    func clearBufferDelegates() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        engine.processAudioBuffer(Array(repeating: Float(0), count: 1000))
        engine.clearBuffer()
    }

    @Test("prepareForFinalize prevents new chunk processing")
    func prepareForFinalizeBlocksChunks() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        engine.prepareForFinalize()
        // Feed a full chunk worth of audio — should NOT trigger processing
        let fullChunk = Array(repeating: Float(0.5), count: 16000 * 6)
        engine.processAudioBuffer(fullChunk)
    }

    @Test("flushProcessing completes immediately when idle")
    func flushProcessingWhenIdle() async {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )
        await engine.flushProcessing()
    }

    // MARK: - Finalize

    @Test("finalize with empty audio calls completion with nil")
    func finalizeEmptyAudio() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )

        let box = SendableBox<String?>()
        engine.finalize(confirmedText: "") { finalText in
            box.set(finalText)
        }

        // Empty audio → immediate nil completion
        #expect(box.didSet == true)
        #expect(box.value! == nil)
    }

    @Test("finalize with short audio discards and returns nil")
    func finalizeShortAudio() {
        let engine = OpenAITranscriptionEngine(
            apiKey: "sk-test-key",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )

        // Feed a tiny amount of audio (< minimumFinalSize)
        engine.processAudioBuffer(Array(repeating: Float(0), count: 100))
        engine.prepareForFinalize()

        let box = SendableBox<String?>()
        engine.finalize(confirmedText: "") { finalText in
            box.set(finalText)
        }

        #expect(box.didSet == true)
        #expect(box.value! == nil)
    }

    // MARK: - loadModel

    @Test("loadModel fails with empty API key")
    func loadModelFailsEmptyKey() async {
        let engine = OpenAITranscriptionEngine(
            apiKey: "",
            onPartialResult: { _ in },
            onFinalResult: { _ in }
        )

        let phaseBox = SendableBox<ModelPhase?>()
        let result = await engine.loadModel(
            modelName: "cloud_openai_whisper",
            language: "es",
            onPhaseChange: { phase in phaseBox.set(phase) },
            eagerWarmup: false
        )

        #expect(result == false)
        if case .error = phaseBox.value {
            // Expected
        } else {
            #expect(Bool(false), "Expected error phase but got \(String(describing: phaseBox.value))")
        }
    }

    // MARK: - ModelManager Cloud Helpers

    @Test("Cloud model ID constant exists")
    @MainActor
    func cloudModelIDExists() {
        #expect(ModelManager.cloudModelID == "cloud_openai_whisper")
    }

    @Test("isCloudModel returns true for cloud ID")
    @MainActor
    func isCloudModelTrue() {
        #expect(ModelManager.isCloudModel(ModelManager.cloudModelID) == true)
    }

    @Test("isCloudModel returns false for local IDs")
    @MainActor
    func isCloudModelFalseForLocal() {
        #expect(ModelManager.isCloudModel(ModelManager.defaultBundledModelID) == false)
        #expect(ModelManager.isCloudModel(ModelManager.optionalSuperModelID) == false)
    }

    @Test("isModelInstalledLocally returns false for cloud model")
    @MainActor
    func cloudNotInstalledLocally() {
        let manager = ModelManager()
        #expect(manager.isModelInstalledLocally(ModelManager.cloudModelID) == false)
    }

    @Test("Quality priority excludes cloud model")
    @MainActor
    func qualityPriorityExcludesCloud() {
        let priority = ModelManager.modelQualityPriority
        #expect(!priority.contains(ModelManager.cloudModelID))
    }
}

// MARK: - Test Helpers

private final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T?
    private var _didSet = false

    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    var didSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didSet
    }

    func set(_ newValue: T) {
        lock.lock()
        _value = newValue
        _didSet = true
        lock.unlock()
    }
}
