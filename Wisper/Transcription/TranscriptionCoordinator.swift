import Foundation

enum TranscriptionInjectionAction: Equatable {
    case none
    case typeText(text: String, clipboardAfterInjection: String)
    case copyToClipboard(String)
}

struct TranscriptionChunkResult: Equatable {
    let confirmedText: String
    let partialText: String
    let metricsText: String?
    let processingMs: Int?
    let action: TranscriptionInjectionAction
}

@MainActor
final class TranscriptionCoordinator {
    private let editingService: DictationEditingService
    private var lastChunkProcessedAt: Date?

    init(editingService: DictationEditingService = DictationEditingService()) {
        self.editingService = editingService
    }

    func resetSession() -> TranscriptionChunkResult {
        editingService.reset()
        lastChunkProcessedAt = nil
        return TranscriptionChunkResult(
            confirmedText: "",
            partialText: "",
            metricsText: nil,
            processingMs: nil,
            action: .none
        )
    }

    func consumePartial(_ text: String, confirmedText: String) -> TranscriptionChunkResult {
        TranscriptionChunkResult(
            confirmedText: confirmedText,
            partialText: text,
            metricsText: nil,
            processingMs: nil,
            action: .none
        )
    }

    func consumeFinal(
        text: String,
        mode: TranscriptionMode,
        confirmedText: String,
        recordingStartedAt: Date?,
        chunkStartedAt: Date,
        now: Date = .now
    ) -> TranscriptionChunkResult {
        if mode == .onRelease,
           let editCommand = TextPostProcessor.editingCommand(in: text)
        {
            if let updated = editingService.applyCommand(editCommand, currentText: confirmedText) {
                lastChunkProcessedAt = now
                return TranscriptionChunkResult(
                    confirmedText: updated,
                    partialText: "",
                    metricsText: nil,
                    processingMs: nil,
                    action: .copyToClipboard(updated)
                )
            }

            lastChunkProcessedAt = now
            return TranscriptionChunkResult(
                confirmedText: confirmedText,
                partialText: "",
                metricsText: nil,
                processingMs: nil,
                action: .none
            )
        }

        if mode == .onRelease,
           let correction = TextPostProcessor.correctionReplacementIfCommand(text)
        {
            editingService.snapshot(currentText: confirmedText)
            let updated = TextPostProcessor.replacingLastSentence(
                in: confirmedText,
                with: correction
            )
            lastChunkProcessedAt = now
            return TranscriptionChunkResult(
                confirmedText: updated,
                partialText: "",
                metricsText: correction,
                processingMs: Int(now.timeIntervalSince(chunkStartedAt) * 1000),
                action: .none
            )
        }

        let separator = TextPostProcessor.separatorForPause(
            since: lastChunkProcessedAt,
            previousText: confirmedText,
            now: now
        )

        let polished = TextPostProcessor.processChunk(
            text,
            mode: .fluent,
            isFirstChunk: confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

        let combined = (separator + polished).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            return TranscriptionChunkResult(
                confirmedText: confirmedText,
                partialText: "",
                metricsText: nil,
                processingMs: nil,
                action: .none
            )
        }

        editingService.snapshot(currentText: confirmedText)
        let updatedConfirmedText = appendChunk(combined, to: confirmedText)
        lastChunkProcessedAt = now
        let processingMs = Int(now.timeIntervalSince(chunkStartedAt) * 1000)

        let action: TranscriptionInjectionAction = if mode == .streaming {
            .typeText(text: combined, clipboardAfterInjection: updatedConfirmedText)
        } else {
            .copyToClipboard(updatedConfirmedText)
        }

        _ = recordingStartedAt // kept for API symmetry with metrics registration in AppState
        return TranscriptionChunkResult(
            confirmedText: updatedConfirmedText,
            partialText: "",
            metricsText: combined,
            processingMs: processingMs,
            action: action
        )
    }

    func finalizedOnReleaseText(confirmedText: String, partialText: String) -> String? {
        let confirmed = confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToInject = !confirmed.isEmpty ? confirmed : partial
        guard !textToInject.isEmpty else { return nil }

        let polished = TextPostProcessor.processFinal(
            textToInject,
            mode: .fluent
        )
        return polished.isEmpty ? nil : polished
    }

    private func appendChunk(_ chunk: String, to existing: String) -> String {
        let chunkTrimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunkTrimmed.isEmpty else { return existing }

        if existing.isEmpty {
            return chunkTrimmed
        }

        if chunk.contains("\n") {
            return existing.trimmingCharacters(in: .whitespaces) + "\n" + chunkTrimmed
        }

        let cleanedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedExisting.isEmpty {
            return chunkTrimmed
        }

        return cleanedExisting + " " + chunkTrimmed
    }
}
