import Foundation
@preconcurrency import WhisperKit

final class TranscriptionEngine: @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var audioAccumulator: [Float] = []
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "com.wisper.transcription", qos: .userInteractive)
    private let accumulatorLock = NSLock()

    // Callbacks
    private let onPartialResult: @Sendable (String) -> Void
    private let onFinalResult: @Sendable (String) -> Void

    // Configuration
    private var language: String = "es"
    private let chunkDurationSeconds: Double = 3.0
    private let sampleRate: Int = 16000

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
        language: String,
        onPhaseChange: @escaping @Sendable (ModelPhase) -> Void
    ) async -> Bool {
        self.language = language
        
        

        do {
            // Single-step: WhisperKit handles download, load, and prewarm.
            print("[Wisper] ====================================")
            print("[Wisper] Starting model load: \(modelName)")
            print("[Wisper] ====================================")

            onPhaseChange(.loading(step: "Preparing \(modelName)..."))

            let config = WhisperKitConfig(
                model: modelName,
                verbose: true,
                prewarm: true,
                load: true,
                download: true
            )

            print("[Wisper] Config created, calling WhisperKit init...")
            whisperKit = try await WhisperKit(config)
            print("[Wisper] ====================================")
            print("[Wisper] MODEL READY")
            print("[Wisper] ====================================")

            onPhaseChange(.ready)
            return true

        } catch {
            let msg = "\(error)"
            print("[Wisper] ====================================")
            print("[Wisper] ERROR: \(msg)")
            print("[Wisper] ====================================")
            onPhaseChange(.error(message: msg))
            return false
        }
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

            Task {
                do {
                    let options = DecodingOptions(
                        language: self.language,
                        temperature: 0,
                        usePrefillPrompt: true,
                        skipSpecialTokens: true,
                        withoutTimestamps: true,
                        clipTimestamps: []
                    )

                    let results = try await whisperKit.transcribe(
                        audioArray: audioToProcess,
                        decodeOptions: options
                    )

                    if let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty
                    {
                        if TranscriptionEngine.isHallucination(text) {
                            print("[Wisper] Filtered hallucination: \(text)")
                        } else {
                            print("[Wisper] Transcribed: \(text)")
                            self.onFinalResult(text)
                        }
                    }
                } catch {
                    print("[Wisper] Transcription error: \(error)")
                }

                self.isProcessing = false
            }
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

            Task {
                do {
                    let options = DecodingOptions(
                        language: self.language,
                        temperature: 0,
                        usePrefillPrompt: true,
                        skipSpecialTokens: true,
                        withoutTimestamps: true,
                        clipTimestamps: []
                    )

                    let results = try await whisperKit.transcribe(
                        audioArray: remainingAudio,
                        decodeOptions: options
                    )

                    if let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty
                    {
                        if TranscriptionEngine.isHallucination(text) {
                            print("[Wisper] Filtered hallucination (final): \(text)")
                        } else {
                            print("[Wisper] Final chunk: \(text)")
                            self.onFinalResult(text)
                        }
                    }
                } catch {
                    print("[Wisper] Final transcription error: \(error)")
                }

                completion?()
            }
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
}
