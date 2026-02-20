import Testing
@testable import Speex

@Suite("Audio Input Tuning")
struct AudioEngineTuningTests {

    @Test("Input gain boosts low-amplitude samples")
    func gainBoostsSamples() {
        let input: [Float] = [0.05, -0.05]
        let output = AudioEngine.applyInputTuning(to: input, gain: 2.0, noiseGate: 0)
        #expect(output[0] > input[0])
        #expect(output[1] < input[1])
    }

    @Test("Noise gate zeroes tiny values")
    func noiseGateRemovesTinyNoise() {
        let input: [Float] = [0.001, -0.002, 0.01]
        let output = AudioEngine.applyInputTuning(to: input, gain: 1.0, noiseGate: 0.005)
        #expect(output[0] == 0)
        #expect(output[1] == 0)
        #expect(output[2] != 0)
    }

    @Test("Friendly input name replaces default aggregate with human-readable label")
    func friendlyInputNameForAggregateDefault() {
        let name = AudioEngine.friendlyInputDeviceName(
            rawName: "Default Device Aggregate",
            uid: "uid-1",
            defaultUID: "uid-1"
        )
        #expect(name == "Micrófono del sistema (por defecto)")
    }

    @Test("Friendly input name appends default marker for regular devices")
    func friendlyInputNameMarksDefaultDevice() {
        let name = AudioEngine.friendlyInputDeviceName(
            rawName: "MacBook Pro Microphone",
            uid: "uid-1",
            defaultUID: "uid-1"
        )
        #expect(name == "MacBook Pro Microphone (por defecto)")
    }
}
