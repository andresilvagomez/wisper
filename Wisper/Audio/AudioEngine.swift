@preconcurrency import AVFoundation
import Foundation

final class AudioEngine: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var isCapturing = false
    private let targetSampleRate: Double = 16000
    private var converter: AVAudioConverter?

    typealias AudioBufferHandler = @Sendable ([Float]) -> Void
    typealias AudioLevelHandler = @Sendable (Float) -> Void

    func startCapture(onBuffer: @escaping AudioBufferHandler, onLevel: AudioLevelHandler? = nil) {
        guard !isCapturing else { return }

        engine = AVAudioEngine()
        guard let engine else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Whisper expects 16kHz mono float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[AudioEngine] Failed to create target format")
            return
        }

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate
            )

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let inputBuffer = buffer
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error, error == nil else {
                print("[AudioEngine] Conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            if let channelData = convertedBuffer.floatChannelData?[0] {
                let frameLength = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(
                    start: channelData,
                    count: frameLength
                ))
                onBuffer(samples)

                // Calculate RMS level for visualization
                if let onLevel {
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        sum += samples[i] * samples[i]
                    }
                    let rms = sqrt(sum / Float(max(frameLength, 1)))
                    // Normalize to 0-1 range (typical speech RMS is 0.01-0.3)
                    let normalized = min(1.0, rms * 5.0)
                    onLevel(normalized)
                }
            }
        }

        do {
            try engine.start()
            isCapturing = true
            print("[AudioEngine] Capture started")
        } catch {
            print("[AudioEngine] Failed to start: \(error)")
        }
    }

    func stopCapture() {
        guard isCapturing else { return }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        isCapturing = false
        print("[AudioEngine] Capture stopped")
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
