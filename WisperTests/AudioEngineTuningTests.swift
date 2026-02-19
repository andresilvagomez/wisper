import Testing
@testable import Wisper

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
}

