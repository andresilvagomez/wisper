import Foundation
import Testing
@testable import Speex

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

    @Test("Streaming chunk with same confirmedText still appends new text")
    func streamingChunkAppendsToConfirmed() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 7_000)

        // First chunk
        let first = coordinator.consumeFinal(
            text: "hola mundo",
            mode: .streaming,
            confirmedText: "",
            recordingStartedAt: start,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.05)
        )

        // Second chunk: new text appended to the confirmed
        let second = coordinator.consumeFinal(
            text: "hola mundo",
            mode: .streaming,
            confirmedText: first.confirmedText,
            recordingStartedAt: start,
            chunkStartedAt: start.addingTimeInterval(0.1),
            now: start.addingTimeInterval(0.15)
        )

        // Coordinator always appends — dedup of late chunks happens
        // at AppState level (guard isRecording) not here.
        #expect(second.confirmedText.count > first.confirmedText.count,
                "Second chunk should extend confirmedText")

        switch second.action {
        case let .typeText(text, _):
            #expect(text.isEmpty == false, "Delta should contain the new appended text")
        default:
            Issue.record("Expected .typeText action for streaming chunk")
        }
    }

    @Test("Streaming chunks produce incremental deltas")
    func streamingIncrementalDeltas() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 8_000)

        let first = coordinator.consumeFinal(
            text: "buenos días",
            mode: .streaming,
            confirmedText: "",
            recordingStartedAt: start,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.03)
        )

        let second = coordinator.consumeFinal(
            text: "cómo estás",
            mode: .streaming,
            confirmedText: first.confirmedText,
            recordingStartedAt: start,
            chunkStartedAt: start.addingTimeInterval(0.2),
            now: start.addingTimeInterval(0.23)
        )

        // Second delta should only contain the NEW text, not repeat the first chunk
        switch second.action {
        case let .typeText(text, _):
            #expect(text.lowercased().contains("buenos") == false,
                    "Second delta should not repeat first chunk text")
        default:
            Issue.record("Expected .typeText action for second streaming chunk")
        }
    }

    // MARK: - Streaming Finalize Fallback

    @Test("Streaming first chunk with empty confirmed returns full text")
    func streamingFirstChunkReturnsFullText() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 10_000)

        let result = coordinator.consumeFinal(
            text: "ahora estoy probando el streaming",
            mode: .streaming,
            confirmedText: "",
            recordingStartedAt: start,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.05)
        )

        // When confirmedText is empty, the full text should be in the typeText action
        switch result.action {
        case let .typeText(text, clipboardAfterInjection):
            #expect(text.lowercased().contains("probando"))
            #expect(clipboardAfterInjection == result.confirmedText)
        default:
            Issue.record("Expected .typeText action for first streaming chunk")
        }
    }

    @Test("finalizedOnReleaseText returns nil for empty text")
    func finalizedOnReleaseTextNilForEmpty() {
        let coordinator = TranscriptionCoordinator()
        let text = coordinator.finalizedOnReleaseText(
            confirmedText: "",
            partialText: ""
        )
        #expect(text == nil)
    }

    @Test("finalizedOnReleaseText returns nil for whitespace-only text")
    func finalizedOnReleaseTextNilForWhitespace() {
        let coordinator = TranscriptionCoordinator()
        let text = coordinator.finalizedOnReleaseText(
            confirmedText: "   \n  ",
            partialText: ""
        )
        #expect(text == nil)
    }

    @Test("finalizedOnReleaseText falls back to partial when confirmed is empty")
    func finalizedOnReleaseTextFallsBackToPartial() {
        let coordinator = TranscriptionCoordinator()
        let text = coordinator.finalizedOnReleaseText(
            confirmedText: "",
            partialText: "texto parcial"
        )
        #expect(text != nil)
        #expect(text!.lowercased().contains("parcial"))
    }

    @Test("Streaming fallback produces injectable text after consumeFinal")
    func streamingFallbackProducesTextAfterConsumeFinal() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 11_000)

        // Simulate finalize delta being consumed (like cloud model finalize)
        let result = coordinator.consumeFinal(
            text: "probando la inyección de texto",
            mode: .streaming,
            confirmedText: "",
            recordingStartedAt: start,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.1)
        )

        // After consuming the finalize delta, finalizedOnReleaseText should
        // produce injectable text from the updated confirmedText
        let polished = coordinator.finalizedOnReleaseText(
            confirmedText: result.confirmedText,
            partialText: result.partialText
        )
        #expect(polished != nil, "Streaming fallback should have text to inject after finalize")
        #expect(polished!.isEmpty == false)
    }

    @Test("On-release consumeFinal produces copyToClipboard, not typeText")
    func onReleaseProducesCopyAction() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 12_000)

        let result = coordinator.consumeFinal(
            text: "texto de prueba",
            mode: .onRelease,
            confirmedText: "",
            recordingStartedAt: start,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.05)
        )

        switch result.action {
        case .copyToClipboard:
            break // Expected
        default:
            Issue.record("On-release mode should produce .copyToClipboard, not \(result.action)")
        }
    }

    // MARK: - Punctuation

    @Test("No inserta espacio antes de puntuación entre bloques")
    func noSpaceBeforePunctuationAcrossChunks() {
        let coordinator = TranscriptionCoordinator()
        let start = Date(timeIntervalSince1970: 9_000)

        let first = coordinator.consumeFinal(
            text: "a la hora de crear por tarjeta",
            mode: .streaming,
            confirmedText: "",
            recordingStartedAt: start,
            chunkStartedAt: start,
            now: start.addingTimeInterval(0.03)
        )

        let second = coordinator.consumeFinal(
            text: "punto via API",
            mode: .streaming,
            confirmedText: first.confirmedText,
            recordingStartedAt: start,
            chunkStartedAt: start.addingTimeInterval(0.2),
            now: start.addingTimeInterval(0.23)
        )

        #expect(second.confirmedText.contains(" . ") == false)
        #expect(second.confirmedText.contains(". via") == true)

        switch second.action {
        case let .typeText(text, _):
            #expect(text == ". via API")
        default:
            Issue.record("Expected .typeText action for punctuation chunk")
        }
    }
}
