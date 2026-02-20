import Foundation
import Testing
@testable import Wisper

@Suite("Transcription Coordinator")
@MainActor
struct TranscriptionCoordinatorTests {
    @Test("Streaming chunk emits typeText action and metrics")
    func streamingChunkFlow() {
        let coordinator = TranscriptionCoordinator()
        let chunkStartedAt = Date(timeIntervalSince1970: 1_000)
        let now = chunkStartedAt.addingTimeInterval(0.08)

        let result = coordinator.consumeFinal(
            text: "hola mundo",
            mode: .streaming,
            confirmedText: "",
            recordingStartedAt: chunkStartedAt,
            chunkStartedAt: chunkStartedAt,
            now: now
        )

        #expect(result.confirmedText.isEmpty == false)
        #expect(result.partialText == "")
        #expect(result.metricsText?.isEmpty == false)
        #expect((result.processingMs ?? 0) >= 70)

        switch result.action {
        case let .typeText(text, clipboardAfterInjection):
            #expect(text.isEmpty == false)
            #expect(clipboardAfterInjection == result.confirmedText)
        default:
            Issue.record("Expected .typeText action for streaming mode")
        }
    }

    @Test("On release edit command updates text and copies to clipboard")
    func onReleaseEditCommand() {
        let coordinator = TranscriptionCoordinator()
        let result = coordinator.consumeFinal(
            text: "borra última frase",
            mode: .onRelease,
            confirmedText: "Primera frase. Segunda frase.",
            recordingStartedAt: nil,
            chunkStartedAt: .now
        )

        #expect(result.confirmedText == "Primera frase.")
        #expect(result.partialText == "")
        #expect(result.metricsText == nil)

        switch result.action {
        case let .copyToClipboard(text):
            #expect(text == "Primera frase.")
        default:
            Issue.record("Expected .copyToClipboard action for edit command")
        }
    }

    @Test("On release correction updates sentence without injection action")
    func onReleaseCorrectionCommand() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 5_000)

        let result = coordinator.consumeFinal(
            text: "no, quise decir llegamos temprano",
            mode: .onRelease,
            confirmedText: "Vamos hoy. Llegamos tarde.",
            recordingStartedAt: nil,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.04)
        )

        #expect(result.confirmedText == "Vamos hoy. Llegamos temprano.")
        #expect(result.metricsText == "Llegamos temprano.")
        #expect((result.processingMs ?? 0) >= 35)
        #expect(result.action == .none)
    }

    @Test("Finalized on release text prioritizes confirmed transcript")
    func finalizedOnReleaseText() {
        let coordinator = TranscriptionCoordinator()
        let text = coordinator.finalizedOnReleaseText(
            confirmedText: "hola mundo",
            partialText: "parcial"
        )

        #expect(text == "Hola mundo.")
    }
}
