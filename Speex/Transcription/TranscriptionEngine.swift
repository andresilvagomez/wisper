import Foundation
@preconcurrency import WhisperKit

final class TranscriptionEngine: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var audioAccumulator: [Float] = []
    private var fullSessionAudio: [Float] = []
    private var isProcessing = false
    private var isShuttingDown = false
    private let processingQueue = DispatchQueue(label: "com.speex.transcription", qos: .userInteractive)
    private let accumulatorLock = NSLock()

    // Callbacks
    private let onPartialResult: @Sendable (String) -> Void
    private let onFinalResult: @Sendable (String) -> Void

    // Configuration
    private var language: String?
    private let chunkDurationSeconds: Double = 5.0
    private let sampleRate: Int = 16000
    private let modelDownloadMaxAttempts = 3
    private var hasPrimedDecoder = false

    // Context carryover between chunks
    private var lastTranscriptionTokens: [Int] = []
    private var sessionLanguage: String?
    private let maxPromptTokens: Int = 224

    // Audio overlap between chunks
    private let overlapDurationSeconds: Double = 0.5
    private let minimumFinalDurationSeconds: Double = 0.15
    private let finalRetranscriptionSeconds: Double = 25.0

    // Whisper hallucination patterns — exact match only to avoid filtering legitimate text
    static let hallucinationExactPhrases: [String] = [
        "[música]", "[music]", "[musica]",
        "[aplausos]", "[applause]",
        "[risas]", "[laughter]",
        "[silencio]", "[silence]",
        "[inaudible]",
        "(música)", "(music)", "(musica)",
        "gracias por ver",
        "subtítulos",
        "thanks for watching",
        "subscribe",
        "suscríbete",
        "like and subscribe",
        "dale like",
    ]
    // Symbols that indicate hallucination when present anywhere
    static let hallucinationSymbols: [Character] = ["♪", "♫"]
    static let leadingArtifactPrefixes: [String] = [
        "thank you",
        "thanks",
    ]

    private var chunkSize: Int {
        Int(chunkDurationSeconds * Double(sampleRate))
    }

    private var overlapSize: Int {
        Int(overlapDurationSeconds * Double(sampleRate))
    }

    private var minimumFinalSize: Int {
        Int(minimumFinalDurationSeconds * Double(sampleRate))
    }

    private var finalRetranscriptionSize: Int {
        Int(finalRetranscriptionSeconds * Double(sampleRate))
    }

    private func buildDecodingOptions() -> DecodingOptions {
        let effectiveLanguage = sessionLanguage ?? language
        let promptTokens: [Int]? = lastTranscriptionTokens.isEmpty
            ? nil
            : Array(lastTranscriptionTokens.suffix(maxPromptTokens))

        return DecodingOptions(
            language: effectiveLanguage,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: effectiveLanguage == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            clipTimestamps: [],
            promptTokens: promptTokens,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0
        )
    }

    /// Relaxed options for the final chunk — user explicitly stopped, so speech is expected.
    /// Removes noSpeechThreshold and quality filters that reject short segments.
    private func buildFinalDecodingOptions() -> DecodingOptions {
        let effectiveLanguage = sessionLanguage ?? language
        let promptTokens: [Int]? = lastTranscriptionTokens.isEmpty
            ? nil
            : Array(lastTranscriptionTokens.suffix(maxPromptTokens))

        return DecodingOptions(
            language: effectiveLanguage,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: effectiveLanguage == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            clipTimestamps: [],
            promptTokens: promptTokens,
            suppressBlank: true
        )
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
            let options = buildDecodingOptions()

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
                    downloadBase: Self.modelsBaseURL,
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

    /// Prevents new chunk processing so all remaining audio flows
    /// to `finalize()` as a single contiguous block.  Call immediately
    /// when recording stops, before the grace-period / stopCapture.
    func prepareForFinalize() {
        accumulatorLock.lock()
        isShuttingDown = true
        accumulatorLock.unlock()
    }

    func processAudioBuffer(_ samples: [Float]) {
        accumulatorLock.lock()
        audioAccumulator.append(contentsOf: samples)
        fullSessionAudio.append(contentsOf: samples)
        let currentLength = audioAccumulator.count
        let shuttingDown = isShuttingDown
        accumulatorLock.unlock()

        if currentLength >= chunkSize && !isProcessing && !shuttingDown {
            processAccumulatedAudio()
        }
    }

    private func processAccumulatedAudio() {
        guard let whisperKit, !isProcessing else { return }

        // Keep last 0.5s as overlap for context continuity at chunk boundaries
        accumulatorLock.lock()
        let audioToProcess = audioAccumulator
        if audioAccumulator.count > overlapSize {
            audioAccumulator = Array(audioAccumulator.suffix(overlapSize))
        } else {
            audioAccumulator.removeAll()
        }
        accumulatorLock.unlock()

        guard !audioToProcess.isEmpty else { return }

        isProcessing = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            let waitForCompletion = DispatchSemaphore(value: 0)

            Task {
                do {
                    let options = self.buildDecodingOptions()

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

                    if !results.isEmpty {
                        // Save tokens from the last result for context carryover
                        if let lastResult = results.last {
                            let tokens = lastResult.segments.flatMap(\.tokens)
                            if !tokens.isEmpty {
                                self.lastTranscriptionTokens = tokens
                            }
                        }

                        // Lock language after first successful detection
                        if self.sessionLanguage == nil, self.language == nil {
                            if let detected = results.first?.language, !detected.isEmpty {
                                self.sessionLanguage = detected
                                print("[Speex] Language locked for session: \(detected)")
                            }
                        }

                        // Concatenate text from ALL results — WhisperKit may
                        // return multiple TranscriptionResult objects.
                        let text = results
                            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")

                        guard !text.isEmpty else {
                            self.isProcessing = false
                            waitForCompletion.signal()
                            return
                        }

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

    /// Re-transcribes the tail of the full session audio to recover any text
    /// that chunk-based processing may have truncated at sentence boundaries.
    ///
    /// - Parameters:
    ///   - confirmedText: The text already confirmed by chunk processing.
    ///     Used to extract only the **new** tail from the retranscription.
    ///   - completion: Called when done. Receives the delta text (or `nil`).
    ///     When provided, `onFinalResult` is skipped to avoid races.
    func finalize(confirmedText: String = "", completion: (@Sendable (_ finalText: String?) -> Void)? = nil) {
        accumulatorLock.lock()
        let audioForFinal: [Float]
        if fullSessionAudio.count > finalRetranscriptionSize {
            audioForFinal = Array(fullSessionAudio.suffix(finalRetranscriptionSize))
        } else {
            audioForFinal = fullSessionAudio
        }
        audioAccumulator.removeAll()
        fullSessionAudio.removeAll()
        isShuttingDown = false
        accumulatorLock.unlock()

        let audioDuration = Double(audioForFinal.count) / Double(sampleRate)
        print("[Speex] Finalize: retranscribing \(audioForFinal.count) samples (\(String(format: "%.2f", audioDuration))s)")

        guard let whisperKit, audioForFinal.count >= minimumFinalSize else {
            if !audioForFinal.isEmpty {
                print("[Speex] Discarding short final audio: \(audioForFinal.count) samples (\(String(format: "%.2f", audioDuration))s)")
            }
            completion?(nil)
            return
        }

        let confirmedSnapshot = confirmedText

        processingQueue.async { [weak self] in
            guard let self else {
                completion?(nil)
                return
            }
            let waitForCompletion = DispatchSemaphore(value: 0)

            Task {
                var producedText: String?
                do {
                    let options = self.buildFinalDecodingOptions()

                    let results = try await whisperKit.transcribe(
                        audioArray: audioForFinal,
                        decodeOptions: options
                    )

                    let text = results
                        .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    if !text.isEmpty {
                        let cleanedText = TranscriptionEngine.sanitizedLeadingArtifacts(from: text)
                        if cleanedText.isEmpty {
                            print("[Speex] Filtered leading artifact final: \(text)")
                        } else if TranscriptionEngine.isHallucination(cleanedText) {
                            print("[Speex] Filtered hallucination (final): \(cleanedText)")
                        } else {
                            print("[Speex] Final retranscription: \(cleanedText)")
                            let delta = TranscriptionEngine.extractNewTail(
                                retranscribed: cleanedText,
                                alreadyConfirmed: confirmedSnapshot
                            )
                            if let delta, !delta.isEmpty {
                                print("[Speex] Final delta: \(delta)")
                                producedText = delta
                            } else {
                                print("[Speex] No new text in retranscription (already confirmed)")
                            }
                        }
                    }
                } catch {
                    print("[Speex] Final transcription error: \(error)")
                }

                if let completion {
                    completion(producedText)
                } else if let producedText {
                    self.onFinalResult(producedText)
                }

                waitForCompletion.signal()
            }

            waitForCompletion.wait()
        }
    }

    /// Waits for any in-progress chunk transcription to complete.
    /// Call before `finalize()` to ensure no audio is lost when
    /// `processAccumulatedAudio` is still running on the processing queue.
    func flushProcessing() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            processingQueue.async {
                continuation.resume()
            }
        }
    }

    func resetSession() {
        accumulatorLock.lock()
        audioAccumulator.removeAll()
        fullSessionAudio.removeAll()
        isShuttingDown = false
        accumulatorLock.unlock()
        lastTranscriptionTokens.removeAll()
        sessionLanguage = nil
    }

    func clearBuffer() {
        resetSession()
    }

    /// Extracts only the NEW text from a retranscription that is not already
    /// present in `alreadyConfirmed`. Uses the last few words of confirmed text
    /// as an anchor to find where new content begins in the retranscription.
    static func extractNewTail(retranscribed: String, alreadyConfirmed: String) -> String? {
        let confirmed = alreadyConfirmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = retranscribed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !full.isEmpty else { return nil }
        guard !confirmed.isEmpty else { return full }

        let confirmedWords = confirmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let fullWords = full.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard confirmedWords.count >= 2, fullWords.count >= 2 else { return full }

        let maxAnchor = min(10, confirmedWords.count, fullWords.count)

        for anchorLen in stride(from: maxAnchor, through: 2, by: -1) {
            let anchorWords = Array(confirmedWords.suffix(anchorLen))
            let searchEnd = fullWords.count - anchorLen
            guard searchEnd >= 0 else { continue }

            // Search from the end — the anchor is expected near the tail
            for i in stride(from: searchEnd, through: 0, by: -1) {
                var matches = true
                for j in 0..<anchorLen {
                    let a = stripPunctuation(anchorWords[j]).lowercased()
                    let b = stripPunctuation(fullWords[i + j]).lowercased()
                    if a != b { matches = false; break }
                }
                if matches {
                    let deltaStart = i + anchorLen
                    if deltaStart >= fullWords.count { return nil }
                    return fullWords[deltaStart...].joined(separator: " ")
                }
            }
        }

        // No anchor found — return full retranscription as fallback
        return full
    }

    private static func stripPunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// Returns true if the text is a known Whisper hallucination
    static func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or very short (1-2 chars)
        if lower.count < 3 { return true }

        // Exact match against known hallucination phrases
        for phrase in hallucinationExactPhrases {
            if lower == phrase { return true }
        }

        // Music symbols anywhere in text
        for symbol in hallucinationSymbols {
            if lower.contains(symbol) { return true }
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

    static let modelsBaseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let base = appSupport
            .appendingPathComponent("Speex", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func localModelFolder(for modelName: String) -> URL {
        modelsBaseURL
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
    }

    static func migrateModelsFromDocumentsIfNeeded() {
        let fm = FileManager.default
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let oldRoot = documentsURL.appendingPathComponent("huggingface", isDirectory: true)
        guard fm.fileExists(atPath: oldRoot.path) else { return }

        let newRoot = modelsBaseURL.appendingPathComponent("huggingface", isDirectory: true)
        if !fm.fileExists(atPath: newRoot.path) {
            do {
                try fm.moveItem(at: oldRoot, to: newRoot)
                print("[Speex] Migrated models from Documents to Application Support")
            } catch {
                print("[Speex] Migration failed, copying instead: \(error)")
                try? fm.copyItem(at: oldRoot, to: newRoot)
                try? fm.removeItem(at: oldRoot)
            }
        } else {
            // New location already has data, just clean up old
            try? fm.removeItem(at: oldRoot)
            print("[Speex] Removed old Documents/huggingface (already migrated)")
        }
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
