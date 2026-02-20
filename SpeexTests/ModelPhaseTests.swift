import Testing
@testable import Speex

@Suite("ModelPhase")
struct ModelPhaseTests {

    @Test("idle is not ready and not active")
    func idle() {
        let phase = ModelPhase.idle
        #expect(!phase.isReady)
        #expect(!phase.isActive)
        #expect(phase.downloadProgress == nil)
        #expect(phase.loadingStep == nil)
        #expect(phase.errorMessage == nil)
    }

    @Test("downloading is active but not ready")
    func downloading() {
        let phase = ModelPhase.downloading(progress: 0.5)
        #expect(!phase.isReady)
        #expect(phase.isActive)
        #expect(phase.downloadProgress == 0.5)
    }

    @Test("loading is active but not ready")
    func loading() {
        let phase = ModelPhase.loading(step: "Compiling CoreML...")
        #expect(!phase.isReady)
        #expect(phase.isActive)
        #expect(phase.loadingStep == "Compiling CoreML...")
    }

    @Test("ready is ready and not active")
    func ready() {
        let phase = ModelPhase.ready
        #expect(phase.isReady)
        #expect(!phase.isActive)
    }

    @Test("error is not ready and not active")
    func error() {
        let phase = ModelPhase.error(message: "Something failed")
        #expect(!phase.isReady)
        #expect(!phase.isActive)
        #expect(phase.errorMessage == "Something failed")
    }

    @Test("phases equality")
    func equality() {
        #expect(ModelPhase.idle == ModelPhase.idle)
        #expect(ModelPhase.ready == ModelPhase.ready)
        #expect(ModelPhase.downloading(progress: 0.5) == ModelPhase.downloading(progress: 0.5))
        #expect(ModelPhase.downloading(progress: 0.3) != ModelPhase.downloading(progress: 0.7))
    }
}
