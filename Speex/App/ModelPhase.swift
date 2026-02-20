import Foundation

/// Represents the honest state of model loading.
/// Each phase maps to a distinct UI treatment — no fake progress.
enum ModelPhase: Equatable {
    /// No model loaded, waiting for user action or auto-load
    case idle

    /// Downloading model files from HuggingFace (real progress 0.0–1.0)
    case downloading(progress: Double)

    /// Model files exist locally, loading into memory + CoreML compilation
    /// This can take 1-5+ minutes on first run (CoreML compiles for the specific chip).
    /// Subsequent loads are faster (~10-30s) because CoreML caches the compiled model.
    case loading(step: String)

    /// Model is ready to transcribe
    case ready

    /// Something went wrong
    case error(message: String)

    // MARK: - Convenience

    var isActive: Bool {
        switch self {
        case .downloading, .loading: return true
        default: return false
        }
    }

    var isReady: Bool {
        self == .ready
    }

    var downloadProgress: Double? {
        if case .downloading(let p) = self { return p }
        return nil
    }

    var loadingStep: String? {
        if case .loading(let s) = self { return s }
        return nil
    }

    var errorMessage: String? {
        if case .error(let m) = self { return m }
        return nil
    }
}
