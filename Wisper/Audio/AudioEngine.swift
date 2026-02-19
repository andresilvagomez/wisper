@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class AudioEngine: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var isCapturing = false
    private let targetSampleRate: Double = 16000
    private var converter: AVAudioConverter?

    typealias AudioBufferHandler = @Sendable ([Float]) -> Void
    typealias AudioLevelHandler = @Sendable (Float) -> Void

    func startCapture(
        inputDeviceUID: String? = nil,
        onBuffer: @escaping AudioBufferHandler,
        onLevel: AudioLevelHandler? = nil
    ) -> Bool {
        guard !isCapturing else { return false }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            print("[AudioEngine] ⚠️ Cannot start — microphone not authorized (status: \(status.rawValue))")
            return false
        }

        engine = AVAudioEngine()
        guard let engine else { return false }

        if let inputDeviceUID, !inputDeviceUID.isEmpty {
            _ = setInputDevice(uid: inputDeviceUID, on: engine)
        }

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
            return false
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
                    // Convert RMS to a perceptual range for UI waves:
                    // - floor at -55 dB (silence)
                    // - 0 dB as max
                    let minDb: Float = -55
                    let safeRms = max(rms, 0.000_001)
                    let db = 20 * log10(safeRms)
                    let normalized = max(0, min(1, (db - minDb) / -minDb))
                    onLevel(normalized)
                }
            }
        }

        do {
            try engine.start()
            isCapturing = true
            print("[AudioEngine] Capture started")
            return true
        } catch {
            print("[AudioEngine] Failed to start: \(error)")
            engine.inputNode.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            return false
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

    // MARK: - Input Devices

    static func availableInputDevices() -> [AudioInputDevice] {
        allAudioDeviceIDs()
            .filter { hasInputStreams(deviceID: $0) }
            .compactMap { deviceID in
                guard let uid = uidForAudioDeviceID(deviceID),
                      let name = nameForAudioDeviceID(deviceID)
                else { return nil }
                return AudioInputDevice(id: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDeviceUID() -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else { return nil }
        return uidForAudioDeviceID(deviceID)
    }

    private func setInputDevice(uid: String, on engine: AVAudioEngine) -> Bool {
        guard let deviceID = Self.audioDeviceID(forUID: uid) else {
            print("[AudioEngine] ⚠️ Input device UID not found: \(uid)")
            return false
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            print("[AudioEngine] ⚠️ Input audio unit unavailable")
            return false
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            print("[AudioEngine] ⚠️ Failed selecting input device \(uid), status: \(status)")
            return false
        }

        print("[AudioEngine] Using input device: \(uid)")
        return true
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard dataStatus == noErr else { return [] }
        return deviceIDs
    }

    private static func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        return status == noErr && dataSize > 0
    }

    private static func uidForAudioDeviceID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uidObject: CFTypeRef?
        var size = UInt32(MemoryLayout<CFTypeRef?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &uidObject
        )

        guard status == noErr, let uidObject, let uidString = uidObject as? String else { return nil }
        return uidString
    }

    private static func nameForAudioDeviceID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameObject: CFTypeRef?
        var size = UInt32(MemoryLayout<CFTypeRef?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &size,
            &nameObject
        )

        guard status == noErr, let nameObject, let nameString = nameObject as? String else { return nil }
        return nameString
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        allAudioDeviceIDs().first { deviceID in
            uidForAudioDeviceID(deviceID) == uid
        }
    }
}
