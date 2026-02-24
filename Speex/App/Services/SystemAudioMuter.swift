import CoreAudio
import Foundation

/// Mutes / unmutes the default system output device using the CoreAudio HAL API.
/// Used to silence other apps (meetings, music, etc.) while recording to avoid
/// microphone bleed-through that confuses transcription.
final class SystemAudioMuter: @unchecked Sendable {
    private let lock = NSLock()
    private var wasMutedBeforeCapture = false
    private var didMute = false

    /// Mute the default output device. Saves the previous mute state so
    /// `unmuteSystemAudio()` can restore it correctly.
    func muteSystemAudio() {
        lock.lock()
        defer { lock.unlock() }

        guard let deviceID = defaultOutputDeviceID() else {
            print("[Speex] SystemAudioMuter: no default output device")
            return
        }

        wasMutedBeforeCapture = isMuted(deviceID: deviceID)

        if !wasMutedBeforeCapture {
            setMute(deviceID: deviceID, muted: true)
            didMute = true
            print("[Speex] SystemAudioMuter: muted output device \(deviceID)")
        } else {
            didMute = false
            print("[Speex] SystemAudioMuter: output was already muted — skipping")
        }
    }

    /// Restore the output device to its state before `muteSystemAudio()` was called.
    func unmuteSystemAudio() {
        lock.lock()
        defer { lock.unlock() }

        guard didMute else { return }

        guard let deviceID = defaultOutputDeviceID() else {
            print("[Speex] SystemAudioMuter: no default output device on unmute")
            return
        }

        setMute(deviceID: deviceID, muted: wasMutedBeforeCapture)
        didMute = false
        print("[Speex] SystemAudioMuter: restored output mute state (was muted: \(wasMutedBeforeCapture))")
    }

    /// Emergency restore — always unmutes regardless of saved state.
    /// Call this on app termination to avoid leaving the system muted.
    func forceUnmute() {
        lock.lock()
        defer { lock.unlock() }

        guard didMute else { return }

        if let deviceID = defaultOutputDeviceID() {
            setMute(deviceID: deviceID, muted: false)
            print("[Speex] SystemAudioMuter: force-unmuted on termination")
        }
        didMute = false
    }

    // MARK: - CoreAudio Helpers

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func isMuted(deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { return false }
        return muted != 0
    }

    private func setMute(deviceID: AudioDeviceID, muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        if status != noErr {
            print("[Speex] SystemAudioMuter: setMute failed with status \(status)")
        }
    }
}
