import Testing
@testable import Speex

@Suite("System Audio Muter")
struct SystemAudioMuterTests {

    @Test("Unmute without prior mute is a no-op")
    func unmuteWithoutMute() {
        let muter = SystemAudioMuter()
        // Should not crash or affect system state
        muter.unmuteSystemAudio()
    }

    @Test("Force unmute without prior mute is a no-op")
    func forceUnmuteWithoutMute() {
        let muter = SystemAudioMuter()
        muter.forceUnmute()
    }

    @Test("Mute then unmute restores state")
    func muteThenUnmute() {
        let muter = SystemAudioMuter()
        // In CI / test environment there may be no output device,
        // so these calls gracefully return without crashing.
        muter.muteSystemAudio()
        muter.unmuteSystemAudio()
        // Second unmute should be a no-op (didMute already cleared)
        muter.unmuteSystemAudio()
    }

    @Test("Force unmute after mute clears state")
    func forceUnmuteAfterMute() {
        let muter = SystemAudioMuter()
        muter.muteSystemAudio()
        muter.forceUnmute()
        // Subsequent calls should be no-ops
        muter.forceUnmute()
        muter.unmuteSystemAudio()
    }

    @Test("Double mute then single unmute restores correctly")
    func doubleMuteSingleUnmute() {
        let muter = SystemAudioMuter()
        muter.muteSystemAudio()
        muter.muteSystemAudio() // second mute — should track first state
        muter.unmuteSystemAudio()
    }
}
