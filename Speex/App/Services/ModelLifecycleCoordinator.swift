import Foundation

@MainActor
final class ModelLifecycleCoordinator {
    private var queuedRecordingStartAfterModelReady = false
    private var modelWarmupRetryTask: Task<Void, Never>?

    deinit {
        modelWarmupRetryTask?.cancel()
    }

    func shouldDeferRecordingStart(modelPhase: ModelPhase) -> Bool {
        guard !modelPhase.isReady else { return false }
        queuedRecordingStartAfterModelReady = true
        return true
    }

    func clearQueuedRecordingStart() {
        queuedRecordingStartAfterModelReady = false
    }

    func consumeQueuedRecordingStartIfNeeded(
        isRecording: Bool,
        startRecording: () -> Void
    ) {
        guard queuedRecordingStartAfterModelReady, !isRecording else { return }
        queuedRecordingStartAfterModelReady = false
        startRecording()
    }

    func ensureModelWarmInBackground(
        isRecording: Bool,
        modelPhase: ModelPhase,
        load: @escaping @MainActor () async -> Void
    ) {
        guard !isRecording else { return }
        guard !modelPhase.isActive else { return }
        guard !modelPhase.isReady else { return }

        Task(priority: .userInitiated) {
            await load()
        }
    }

    func scheduleWarmupRetryIfNeeded(
        isRecording: Bool,
        retryDelay: Duration = .seconds(3),
        onRetry: @escaping @MainActor () -> Void
    ) {
        guard !isRecording else { return }
        guard modelWarmupRetryTask == nil else { return }

        modelWarmupRetryTask = Task {
            try? await Task.sleep(for: retryDelay)
            await MainActor.run {
                self.modelWarmupRetryTask = nil
                guard !isRecording else { return }
                onRetry()
            }
        }
    }

    func normalizedSelectedModel(
        selectedModel: String,
        validModelIDs: Set<String>,
        defaultModelID: String
    ) -> String {
        validModelIDs.contains(selectedModel) ? selectedModel : defaultModelID
    }

    func resolvedModelSelection(
        currentSelection: String,
        downloadedModelIDs: Set<String>,
        defaultModelID: String,
        qualityPriority: [String]
    ) -> String {
        guard !downloadedModelIDs.isEmpty else {
            return currentSelection == qualityPriority.first ? currentSelection : defaultModelID
        }

        if downloadedModelIDs.contains(currentSelection) || currentSelection == defaultModelID {
            return currentSelection
        }

        if let bestDownloaded = qualityPriority.first(where: { downloadedModelIDs.contains($0) }) {
            return bestDownloaded
        }

        return currentSelection
    }

    func downloadedModelIDs(
        availableModelIDs: [String],
        fileManager: FileManager = .default
    ) -> Set<String> {
        let modelsRoot = TranscriptionEngine.modelsBaseURL
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)

        return Set(availableModelIDs.compactMap { modelID in
            let modelFolder = modelsRoot.appendingPathComponent(modelID, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: modelFolder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let hasFiles = ((try? fileManager.contentsOfDirectory(atPath: modelFolder.path))?.isEmpty == false)
            return hasFiles ? modelID : nil
        })
    }
}
