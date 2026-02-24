import Foundation

@MainActor
final class ModelManager {

    static let defaultBundledModelID = "openai_whisper-large-v3-v20240930_turbo"
    static let optionalSuperModelID = "openai_whisper-large-v3-v20240930"

    static let availableModels: [(id: String, name: String, size: String)] = [
        (defaultBundledModelID, "Speex Turbo (Predeterminado)", "~632 MB"),
        (optionalSuperModelID, "Speex Super Pro", "~1.5 GB"),
    ]

    /// Priority from highest quality to lowest quality.
    static let modelQualityPriority: [String] = [
        optionalSuperModelID,
        defaultBundledModelID,
    ]

    private let lifecycleCoordinator = ModelLifecycleCoordinator()

    // MARK: - Load

    func loadModel(
        engine: TranscriptionEngine?,
        selectedModel: String,
        selectedLanguage: String,
        onPhaseChange: @escaping @Sendable (ModelPhase) -> Void
    ) async -> Bool {
        let lang = selectedLanguage == "auto"
            ? nil
            : LanguageCatalog.normalizeWhisperLanguageCode(selectedLanguage)

        return await Task.detached(priority: .utility) {
            await engine?.loadModel(
                modelName: selectedModel,
                language: lang,
                onPhaseChange: onPhaseChange,
                eagerWarmup: true
            ) ?? false
        }.value
    }

    func isModelInstalledLocally(_ modelID: String) -> Bool {
        TranscriptionEngine.isModelBundled(modelID) || TranscriptionEngine.isModelDownloaded(modelID)
    }

    // MARK: - Selection

    func normalizeSelectedModel(_ selectedModel: String) -> String {
        let validIDs = Set(Self.availableModels.map(\.id))
        return lifecycleCoordinator.normalizedSelectedModel(
            selectedModel: selectedModel,
            validModelIDs: validIDs,
            defaultModelID: Self.defaultBundledModelID
        )
    }

    func applyBestDownloaded(currentSelection: String) -> String {
        let downloadedModelIDs = lifecycleCoordinator.downloadedModelIDs(
            availableModelIDs: Self.availableModels.map(\.id)
        )
        return lifecycleCoordinator.resolvedModelSelection(
            currentSelection: currentSelection,
            downloadedModelIDs: downloadedModelIDs,
            defaultModelID: Self.defaultBundledModelID,
            qualityPriority: Self.modelQualityPriority
        )
    }

    // MARK: - Lifecycle

    func shouldDeferRecordingStart(modelPhase: ModelPhase) -> Bool {
        lifecycleCoordinator.shouldDeferRecordingStart(modelPhase: modelPhase)
    }

    func clearQueuedRecordingStart() {
        lifecycleCoordinator.clearQueuedRecordingStart()
    }

    func consumeQueuedRecordingStartIfNeeded(
        isRecording: Bool,
        startRecording: @escaping () -> Void
    ) {
        lifecycleCoordinator.consumeQueuedRecordingStartIfNeeded(
            isRecording: isRecording,
            startRecording: startRecording
        )
    }

    func scheduleWarmupRetryIfNeeded(
        isRecording: Bool,
        onRetry: @escaping @Sendable () -> Void
    ) {
        lifecycleCoordinator.scheduleWarmupRetryIfNeeded(
            isRecording: isRecording,
            onRetry: onRetry
        )
    }

    func ensureModelWarmInBackground(
        isRecording: Bool,
        modelPhase: ModelPhase,
        load: @escaping @Sendable () async -> Void
    ) {
        lifecycleCoordinator.ensureModelWarmInBackground(
            isRecording: isRecording,
            modelPhase: modelPhase,
            load: load
        )
    }
}
