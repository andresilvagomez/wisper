import Foundation
import Testing
@testable import Speex

@Suite("Model Lifecycle Coordinator")
@MainActor
struct ModelLifecycleCoordinatorTests {
    @Test("Defers recording start while model is not ready")
    func deferAndConsumeQueuedStart() {
        let coordinator = ModelLifecycleCoordinator()
        let deferred = coordinator.shouldDeferRecordingStart(modelPhase: .loading(step: "x"))
        #expect(deferred == true)

        var started = false
        coordinator.consumeQueuedRecordingStartIfNeeded(
            isRecording: false,
            startRecording: { started = true }
        )
        #expect(started == true)
    }

    @Test("Does not defer recording when model is ready")
    func noDeferWhenReady() {
        let coordinator = ModelLifecycleCoordinator()
        let deferred = coordinator.shouldDeferRecordingStart(modelPhase: .ready)
        #expect(deferred == false)
    }

    @Test("Normalizes invalid selected model to default")
    func normalizeSelectedModel() {
        let coordinator = ModelLifecycleCoordinator()
        let resolved = coordinator.normalizedSelectedModel(
            selectedModel: "invalid-model",
            validModelIDs: ["a", "b"],
            defaultModelID: "a"
        )
        #expect(resolved == "a")
    }

    @Test("Picks best downloaded model by quality priority")
    func resolveBestDownloadedModel() {
        let coordinator = ModelLifecycleCoordinator()
        let resolved = coordinator.resolvedModelSelection(
            currentSelection: "x",
            downloadedModelIDs: ["openai_whisper-large-v3-v20240930_turbo"],
            defaultModelID: "openai_whisper-large-v3-v20240930_turbo",
            qualityPriority: [
                "openai_whisper-large-v3-v20240930",
                "openai_whisper-large-v3-v20240930_turbo",
            ]
        )
        #expect(resolved == "openai_whisper-large-v3-v20240930_turbo")
    }

    @Test("Warmup guard avoids load when already ready")
    func warmupGuardReady() async {
        let coordinator = ModelLifecycleCoordinator()
        var called = false

        coordinator.ensureModelWarmInBackground(
            isRecording: false,
            modelPhase: .ready,
            load: { called = true }
        )

        try? await Task.sleep(for: .milliseconds(20))
        #expect(called == false)
    }
}
