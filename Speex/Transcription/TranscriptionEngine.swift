import Foundation
@preconcurrency import WhisperKit

final class TranscriptionEngine: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var audioAccumulator: [Float] = []
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "com.speex.transcription", qos: .userInteractive)
    private let accumulatorLock = NSLock()

    // Callbacks
    private let onPartialResult: @Sendable (String) -> Void
    private let onFinalResult: @Sendable (String) -> Void

    // Configuration
    private var language: String?
    private let chunkDurationSeconds: Double = 3.0
    private let sampleRate: Int = 16000
    private let modelDownloadMaxAttempts = 3
    private var hasPrimedDecoder = false

    // Whisper hallucination patterns to filter out
    static let hallucinationPatterns: [String] = [
        "[música]", "[music]", "[musica]",
        "[aplausos]", "[applause]",
        "[risas]", "[laughter]",
        "[silencio]", "[silence]",
        "[inaudible]",
        "(música)", "(music)", "(musica)",
        "♪", "♫",
        "gracias por ver",  // common Spanish hallucination
        "subtítulos",       // subtitle hallucination
        "thanks for watching",
        "subscribe",
    ]
    static let leadingArtifactPrefixes: [String] = [
        "thank you",
        "thanks",
    ]

    private var chunkSize: Int {
        Int(chunkDurationSeconds * Double(sampleRate))
    }

    init(
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String) -> Void
    ) {
        self.onPartialResult = onPartialResult
        self.onFinalResult = onFinalResult
    }

    /// Loads the model using WhisperKit's single-step init.
    /// WhisperKit handles download + load + prewarm internally.
    func loadModel(
        modelName: String,
        language: String?,
        onPhaseChange: @escaping @Sendable (ModelPhase) -> Void,
        eagerWarmup: Bool = true
    ) async -> Bool {
        self.language = language
        self.hasPrimedDecoder = false

        do {
            print("[Speex] ====================================")
            print("[Speex] Starting model load: \(modelName)")
            print("[Speex] ====================================")

            onPhaseChange(.downloading(progress: 0))

            let downloadedModelFolder: URL
            if let bundledFolder = Self.bundledModelFolder(for: modelName) {
                downloadedModelFolder = bundledFolder
                onPhaseChange(.loading(step: L10n.t("model.phase.using_bundled")))
            } else if Self.isModelDownloaded(modelName) {
                downloadedModelFolder = Self.localModelFolder(for: modelName)
                onPhaseChange(.loading(step: L10n.t("model.phase.using_local_cache")))
            } else {
                downloadedModelFolder = try await downloadModelWithRetry(
                    modelName: modelName,
                    onPhaseChange: onPhaseChange
                )
            }

            onPhaseChange(.loading(step: L10n.f("model.phase.preparing_named", modelName)))

            let config = WhisperKitConfig(
                modelFolder: downloadedModelFolder.path,
                verbose: true,
                prewarm: eagerWarmup,
                load: true,
                download: false
            )

            print("[Speex] Download complete, calling WhisperKit init...")
            whisperKit = try await withWhisperKitTimeout(seconds: 120) {
                try await WhisperKit(config)
            }

            if eagerWarmup {
                onPhaseChange(.loading(step: L10n.t("model.phase.warming_up")))
                await primeDecoderIfNeeded()
            } else {
                Task.detached(priority: .utility) { [weak self] in
                    await self?.primeDecoderIfNeeded()
                }
            }

            print("[Speex] ====================================")
            print("[Speex] MODEL READY")
            print("[Speex] ====================================")

            onPhaseChange(.ready)
            return true

        } catch {
            let msg = "\(error)"
            print("[Speex] ====================================")
            print("[Speex] ERROR: \(msg)")
            print("[Speex] ====================================")
            onPhaseChange(.error(message: msg))
            return false
        }
    }

    private func primeDecoderIfNeeded() async {
        guard !hasPrimedDecoder, let whisperKit else { return }
        hasPrimedDecoder = true

        do {
            let warmupAudio = Array(repeating: Float(0), count: Int(Double(sampleRate) * 0.35))
            let options = DecodingOptions(
                language: language,
                temperature: 0,
                usePrefillPrompt: true,
                detectLanguage: language == nil,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                clipTimestamps: []
            )

            _ = try await whisperKit.transcribe(
                audioArray: warmupAudio,
                decodeOptions: options
            )
            print("[Speex] ✅ Decoder warmup complete")
        } catch {
            print("[Speex] ⚠️ Decoder warmup failed (non-fatal): \(error)")
        }
    }

    private func withWhisperKitTimeout(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> WhisperKit
    ) async throws -> WhisperKit {
        try await withThrowingTaskGroup(of: WhisperKit.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(
                    domain: "Speex.TranscriptionEngine",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "Model loading timed out"]
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func downloadModelWithRetry(
        modelName: String,
        onPhaseChange: @escaping @Sendable (ModelPhase) -> Void
    ) async throws -> URL {
        var lastError: Error?

        for attempt in 1...modelDownloadMaxAttempts {
            do {
                let folder = try await WhisperKit.download(
                    variant: modelName,
                    progressCallback: { progress in
                        let fraction = max(0, min(1, progress.fractionCompleted))
                        onPhaseChange(.downloading(progress: fraction))
                    }
                )

                guard Self.isModelFolderValid(folder) else {
                    throw NSError(
                        domain: "Speex.TranscriptionEngine",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Downloaded model folder is empty"]
                    )
                }
                return folder
            } catch {
                lastError = error
                print("[Speex] Download attempt \(attempt)/\(modelDownloadMaxAttempts) failed: \(error)")
                if attempt < modelDownloadMaxAttempts {
                    try? await Task.sleep(for: .milliseconds(450 * attempt))
                }
            }
        }

        throw lastError ?? NSError(
            domain: "Speex.TranscriptionEngine",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Model download failed"]
        )
    }

    func processAudioBuffer(_ samples: [Float]) {
        accumulatorLock.lock()
        audioAccumulator.append(contentsOf: samples)
        let currentLength = audioAccumulator.count
        accumulatorLock.unlock()

        if currentLength >= chunkSize && !isProcessing {
            processAccumulatedAudio()
        }
    }

    private func processAccumulatedAudio() {
        guard let whisperKit, !isProcessing else { return }

        // Take the audio and CLEAR the accumulator so we don't re-process
        accumulatorLock.lock()
        let audioToProcess = audioAccumulator
        audioAccumulator.removeAll()
        accumulatorLock.unlock()

        guard !audioToProcess.isEmpty else { return }

        isProcessing = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            let waitForCompletion = DispatchSemaphore(value: 0)

            Task {
                do {
                    let options = DecodingOptions(
                        language: self.language,
                        temperature: 0,
                        usePrefillPrompt: true,
                        detectLanguage: self.language == nil,
                        skipSpecialTokens: true,
                        withoutTimestamps: true,
                        clipTimestamps: []
                    )

                    let results = try await whisperKit.transcribe(
                        audioArray: audioToProcess,
                        decodeOptions: options,
                        callback: { progress in
                            let partial = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !partial.isEmpty {
                                self.onPartialResult(partial)
                            }
                            return nil
                        }
                    )

                    if let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty
                    {
                        let cleanedText = TranscriptionEngine.sanitizedLeadingArtifacts(from: text)
                        guard !cleanedText.isEmpty else {
                            print("[Speex] Filtered leading artifact chunk: \(text)")
                            self.isProcessing = false
                            waitForCompletion.signal()
                            return
                        }

                        if TranscriptionEngine.isHallucination(cleanedText) {
                            print("[Speex] Filtered hallucination: \(cleanedText)")
                        } else {
                            print("[Speex] Transcribed: \(cleanedText)")
                            self.onFinalResult(cleanedText)
                        }
                    }
                } catch {
                    print("[Speex] Transcription error: \(error)")
                }

                self.isProcessing = false
                waitForCompletion.signal()
            }

            waitForCompletion.wait()
        }
    }

    func finalize(completion: (@Sendable () -> Void)? = nil) {
        accumulatorLock.lock()
        let remainingAudio = audioAccumulator
        audioAccumulator.removeAll()
        accumulatorLock.unlock()

        guard let whisperKit, !remainingAudio.isEmpty else {
            completion?()
            return
        }

        processingQueue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            let waitForCompletion = DispatchSemaphore(value: 0)

            Task {
                do {
                    let options = DecodingOptions(
                        language: self.language,
                        temperature: 0,
                        usePrefillPrompt: true,
                        detectLanguage: self.language == nil,
                        skipSpecialTokens: true,
                        withoutTimestamps: true,
                        clipTimestamps: []
                    )

                    let results = try await whisperKit.transcribe(
                        audioArray: remainingAudio,
                        decodeOptions: options,
                        callback: { progress in
                            let partial = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !partial.isEmpty {
                                self.onPartialResult(partial)
                            }
                            return nil
                        }
                    )

                    if let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty
                    {
                        let cleanedText = TranscriptionEngine.sanitizedLeadingArtifacts(from: text)
                        guard !cleanedText.isEmpty else {
                            print("[Speex] Filtered leading artifact final chunk: \(text)")
                            completion?()
                            waitForCompletion.signal()
                            return
                        }

                        if TranscriptionEngine.isHallucination(cleanedText) {
                            print("[Speex] Filtered hallucination (final): \(cleanedText)")
                        } else {
                            print("[Speex] Final chunk: \(cleanedText)")
                            self.onFinalResult(cleanedText)
                        }
                    }
                } catch {
                    print("[Speex] Final transcription error: \(error)")
                }

                completion?()
                waitForCompletion.signal()
            }

            waitForCompletion.wait()
        }
    }

    func clearBuffer() {
        accumulatorLock.lock()
        audioAccumulator.removeAll()
        accumulatorLock.unlock()
    }

    /// Returns true if the text is a known Whisper hallucination
    static func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or very short (1-2 chars)
        if lower.count < 3 { return true }

        // Exact match or contained in hallucination patterns
        for pattern in hallucinationPatterns {
            if lower == pattern || lower.contains(pattern) {
                return true
            }
        }

        // Bracketed/parenthesized text like [anything] or (anything)
        if (lower.hasPrefix("[") && lower.hasSuffix("]")) ||
           (lower.hasPrefix("(") && lower.hasSuffix(")")) {
            return true
        }

        // Only punctuation/symbols
        let stripped = lower.components(separatedBy: .alphanumerics).joined()
        if stripped.count == lower.count { return true }

        return false
    }

    static func sanitizedLeadingArtifacts(from text: String) -> String {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return "" }

        for prefix in leadingArtifactPrefixes {
            let lower = candidate.lowercased()
            guard lower.hasPrefix(prefix) else { continue }

            let remainder = candidate.dropFirst(prefix.count)
            let cleanedRemainder = remainder.drop {
                $0.isWhitespace || ",.!?:;…-–—".contains($0)
            }

            // If it's only the artifact phrase, drop it completely.
            if cleanedRemainder.isEmpty {
                return ""
            }

            candidate = String(cleanedRemainder)
            break
        }

        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func localModelFolder(for modelName: String) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return documentsURL
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
    }

    static func isModelDownloaded(_ modelName: String) -> Bool {
        isModelFolderValid(localModelFolder(for: modelName))
    }

    static func bundledModelFolder(for modelName: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let modelFolder = resourceURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)

        return isModelFolderValid(modelFolder) ? modelFolder : nil
    }

    static func isModelBundled(_ modelName: String) -> Bool {
        bundledModelFolder(for: modelName) != nil
    }

    static func isModelFolderValid(_ folderURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return !children.isEmpty
    }
}
