import Foundation

// MARK: - Error Types

enum OpenAITranscriptionError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key requerida"
        case .invalidAPIKey:
            return "API key inválida"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .apiError(let statusCode, let message):
            return "Error \(statusCode): \(message)"
        }
    }
}

// MARK: - Cloud Transcription Engine

final class OpenAITranscriptionEngine: TranscriptionProvider, @unchecked Sendable {

    // MARK: - Audio Buffers

    private var audioAccumulator: [Float] = []
    private var fullSessionAudio: [Float] = []
    private var isProcessing = false
    private var isShuttingDown = false
    private let processingQueue = DispatchQueue(label: "com.speex.cloud-transcription", qos: .userInteractive)
    private let accumulatorLock = NSLock()

    // MARK: - Callbacks

    private let onPartialResult: @Sendable (String) -> Void
    private let onFinalResult: @Sendable (String) -> Void

    // MARK: - Configuration

    private let apiKey: String
    private var language: String?
    private let apiModel = "whisper-1"

    private let chunkDurationSeconds: Double = 5.0
    private let sampleRate: Int = 16000
    private let overlapDurationSeconds: Double = 0.5
    private let minimumFinalDurationSeconds: Double = 0.15
    private let finalRetranscriptionSeconds: Double = 25.0

    private var chunkSize: Int { Int(chunkDurationSeconds * Double(sampleRate)) }
    private var overlapSize: Int { Int(overlapDurationSeconds * Double(sampleRate)) }
    private var minimumFinalSize: Int { Int(minimumFinalDurationSeconds * Double(sampleRate)) }
    private var finalRetranscriptionSize: Int { Int(finalRetranscriptionSeconds * Double(sampleRate)) }

    // MARK: - Init

    init(
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (String) -> Void
    ) {
        self.apiKey = apiKey
        self.onPartialResult = onPartialResult
        self.onFinalResult = onFinalResult
    }

    // MARK: - TranscriptionProvider

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

    func resetSession() {
        accumulatorLock.lock()
        audioAccumulator.removeAll()
        fullSessionAudio.removeAll()
        isShuttingDown = false
        accumulatorLock.unlock()
    }

    func prepareForFinalize() {
        accumulatorLock.lock()
        isShuttingDown = true
        accumulatorLock.unlock()
    }

    func flushProcessing() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            processingQueue.async {
                continuation.resume()
            }
        }
    }

    func finalize(confirmedText: String, completion: (@Sendable (_ finalText: String?) -> Void)?) {
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
        print("[Speex Cloud] Finalize: retranscribing \(audioForFinal.count) samples (\(String(format: "%.2f", audioDuration))s)")

        guard audioForFinal.count >= minimumFinalSize else {
            if !audioForFinal.isEmpty {
                print("[Speex Cloud] Discarding short final audio: \(audioForFinal.count) samples")
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
            let sem = DispatchSemaphore(value: 0)

            Task {
                var producedText: String?
                do {
                    let wavData = self.encodeWAV(samples: audioForFinal)
                    let text = try await self.transcribeWithOpenAI(audioData: wavData)

                    if !text.isEmpty {
                        let cleaned = TranscriptionEngine.sanitizedLeadingArtifacts(from: text)
                        if cleaned.isEmpty {
                            print("[Speex Cloud] Filtered leading artifact final: \(text)")
                        } else if TranscriptionEngine.isHallucination(cleaned) {
                            print("[Speex Cloud] Filtered hallucination (final): \(cleaned)")
                        } else {
                            print("[Speex Cloud] Final retranscription: \(cleaned)")
                            let delta = TranscriptionEngine.extractNewTail(
                                retranscribed: cleaned,
                                alreadyConfirmed: confirmedSnapshot
                            )
                            if let delta, !delta.isEmpty {
                                print("[Speex Cloud] Final delta: \(delta)")
                                producedText = delta
                            } else {
                                print("[Speex Cloud] No new text in retranscription")
                            }
                        }
                    }
                } catch {
                    print("[Speex Cloud] Final transcription error: \(error)")
                }

                if let completion {
                    completion(producedText)
                } else if let producedText {
                    self.onFinalResult(producedText)
                }

                sem.signal()
            }

            sem.wait()
        }
    }

    func clearBuffer() {
        resetSession()
    }

    func loadModel(
        modelName: String,
        language: String?,
        onPhaseChange: @escaping @Sendable (ModelPhase) -> Void,
        eagerWarmup: Bool
    ) async -> Bool {
        self.language = language

        guard !apiKey.isEmpty else {
            onPhaseChange(.error(message: L10n.t("cloud.error.no_api_key")))
            return false
        }

        onPhaseChange(.loading(step: L10n.t("cloud.phase.verifying")))

        do {
            try await validateAPIKey()
        } catch {
            if case OpenAITranscriptionError.invalidAPIKey = error {
                onPhaseChange(.error(message: L10n.t("cloud.error.invalid_api_key")))
            } else {
                onPhaseChange(.error(message: "\(error.localizedDescription)"))
            }
            return false
        }

        print("[Speex Cloud] ====================================")
        print("[Speex Cloud] API KEY VALIDATED — ENGINE READY")
        print("[Speex Cloud] ====================================")

        onPhaseChange(.ready)
        return true
    }

    // MARK: - Chunk Processing

    private func processAccumulatedAudio() {
        guard !isProcessing else { return }

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
            let sem = DispatchSemaphore(value: 0)

            Task {
                do {
                    let wavData = self.encodeWAV(samples: audioToProcess)
                    let text = try await self.transcribeWithOpenAI(audioData: wavData)

                    guard !text.isEmpty else {
                        self.isProcessing = false
                        sem.signal()
                        return
                    }

                    let cleaned = TranscriptionEngine.sanitizedLeadingArtifacts(from: text)
                    guard !cleaned.isEmpty else {
                        print("[Speex Cloud] Filtered leading artifact chunk: \(text)")
                        self.isProcessing = false
                        sem.signal()
                        return
                    }

                    if TranscriptionEngine.isHallucination(cleaned) {
                        print("[Speex Cloud] Filtered hallucination: \(cleaned)")
                    } else {
                        print("[Speex Cloud] Transcribed: \(cleaned)")
                        self.onFinalResult(cleaned)
                    }
                } catch {
                    print("[Speex Cloud] Transcription error: \(error)")
                }

                self.isProcessing = false
                sem.signal()
            }

            sem.wait()
        }
    }

    // MARK: - OpenAI API

    private func validateAPIKey() async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models/whisper-1")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw OpenAITranscriptionError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAITranscriptionError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Key validation failed"
            )
        }
    }

    private func transcribeWithOpenAI(audioData: Data) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        // model
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(apiModel)\r\n")

        // language (optional)
        if let lang = language {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.append("\(lang)\r\n")
        }

        // response_format
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("text\r\n")

        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw OpenAITranscriptionError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAITranscriptionError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorText
            )
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - WAV Encoding

    /// Encodes Float32 PCM samples (16 kHz mono) into a WAV file in memory.
    private func encodeWAV(samples: [Float]) -> Data {
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateU32 = UInt32(sampleRate)
        let byteRate = sampleRateU32 * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var data = Data(capacity: 44 + Int(dataSize))

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.appendLittleEndian(chunkSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.appendLittleEndian(UInt32(16))                 // subchunk size
        data.appendLittleEndian(UInt16(1))                  // PCM format
        data.appendLittleEndian(numChannels)
        data.appendLittleEndian(sampleRateU32)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)

        // data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.appendLittleEndian(dataSize)

        // PCM samples: Float32 → Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            data.appendLittleEndian(int16)
        }

        return data
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
