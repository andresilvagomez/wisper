import Foundation
import Testing
@testable import Speex

@Suite("Model Manager")
@MainActor
struct ModelManagerTests {

    // MARK: - Static Constants

    @Test("Default bundled model ID matches expected value")
    func defaultBundledModelID() {
        #expect(ModelManager.defaultBundledModelID == "openai_whisper-large-v3-v20240930_turbo")
    }

    @Test("Optional super model ID matches expected value")
    func optionalSuperModelID() {
        #expect(ModelManager.optionalSuperModelID == "openai_whisper-large-v3-v20240930")
    }

    @Test("Available models contains local and cloud entries")
    func availableModelsCount() {
        #expect(ModelManager.availableModels.count == 3)
        let ids = ModelManager.availableModels.map(\.id)
        #expect(ids.contains(ModelManager.defaultBundledModelID))
        #expect(ids.contains(ModelManager.optionalSuperModelID))
        #expect(ids.contains(ModelManager.cloudModelID))
    }

    @Test("Quality priority lists super model before turbo")
    func qualityPriorityOrder() {
        let priority = ModelManager.modelQualityPriority
        #expect(priority.count == 2)
        #expect(priority[0] == ModelManager.optionalSuperModelID)
        #expect(priority[1] == ModelManager.defaultBundledModelID)
    }

    // MARK: - Selection

    @Test("Normalize keeps a valid selected model unchanged")
    func normalizeKeepsValidModel() {
        let manager = ModelManager()
        let result = manager.normalizeSelectedModel(ModelManager.defaultBundledModelID)
        #expect(result == ModelManager.defaultBundledModelID)
    }

    @Test("Normalize falls back to default for an invalid model")
    func normalizeFallsBackForInvalidModel() {
        let manager = ModelManager()
        let result = manager.normalizeSelectedModel("nonexistent-model-id")
        #expect(result == ModelManager.defaultBundledModelID)
    }

    @Test("Apply best downloaded returns current selection when nothing downloaded")
    func applyBestDownloadedFallback() {
        let manager = ModelManager()
        let result = manager.applyBestDownloaded(currentSelection: ModelManager.defaultBundledModelID)
        // When no models are downloaded (CI), it should still return a valid selection
        let validIDs = Set(ModelManager.availableModels.map(\.id))
        #expect(validIDs.contains(result) || result == ModelManager.defaultBundledModelID)
    }

    // MARK: - Lifecycle Delegation

    @Test("Defers recording start while model is loading")
    func defersRecordingWhileLoading() {
        let manager = ModelManager()
        #expect(manager.shouldDeferRecordingStart(modelPhase: .loading(step: "Preparing")) == true)
    }

    @Test("Does not defer recording when model is ready")
    func doesNotDeferWhenReady() {
        let manager = ModelManager()
        #expect(manager.shouldDeferRecordingStart(modelPhase: .ready) == false)
    }

    @Test("Defers recording start while model is downloading")
    func defersRecordingWhileDownloading() {
        let manager = ModelManager()
        #expect(manager.shouldDeferRecordingStart(modelPhase: .downloading(progress: 0.5)) == true)
    }

    @Test("Defers recording when model is idle (not yet loaded)")
    func defersWhenIdle() {
        let manager = ModelManager()
        #expect(manager.shouldDeferRecordingStart(modelPhase: .idle) == true)
    }

    @Test("Clear queued recording start does not crash")
    func clearQueuedRecordingStartSafe() {
        let manager = ModelManager()
        manager.clearQueuedRecordingStart()
    }

    @Test("Consume queued start fires callback when queued")
    func consumeQueuedStartFires() {
        let manager = ModelManager()
        // First defer to queue a start
        _ = manager.shouldDeferRecordingStart(modelPhase: .loading(step: "x"))

        var started = false
        manager.consumeQueuedRecordingStartIfNeeded(
            isRecording: false,
            startRecording: { started = true }
        )
        #expect(started == true)
    }

    @Test("Load model returns false with nil engine")
    func loadModelNilEngine() async {
        let manager = ModelManager()
        let result = await manager.loadModel(
            engine: nil,
            selectedModel: ModelManager.defaultBundledModelID,
            selectedLanguage: "auto",
            onPhaseChange: { _ in }
        )
        #expect(result == false)
    }

    @Test("Warmup guard skips load when already ready")
    func warmupGuardSkipsWhenReady() async {
        let manager = ModelManager()
        let flag = SendableFlag()

        manager.ensureModelWarmInBackground(
            isRecording: false,
            modelPhase: .ready,
            load: { flag.set() }
        )

        try? await Task.sleep(for: .milliseconds(20))
        #expect(flag.value == false)
    }

    @Test("Warmup guard skips load when recording")
    func warmupGuardSkipsWhenRecording() async {
        let manager = ModelManager()
        let flag = SendableFlag()

        manager.ensureModelWarmInBackground(
            isRecording: true,
            modelPhase: .idle,
            load: { flag.set() }
        )

        try? await Task.sleep(for: .milliseconds(20))
        #expect(flag.value == false)
    }
}

// MARK: - Test Helpers

private final class SendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}
