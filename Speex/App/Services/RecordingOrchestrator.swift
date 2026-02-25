import AppKit
import Foundation

@MainActor
final class RecordingOrchestrator {

    let sessionCoordinator = RecordingSessionCoordinator()
    let transcriptionCoordinator = TranscriptionCoordinator()
    let systemAudioMuter = SystemAudioMuter()
    private var overlayController = OverlayWindowController()

    weak var appState: AppState?

    var recordingStartedAt: Date? {
        sessionCoordinator.recordingStartedAt
    }

    // MARK: - Start

    func startRecording() {
        guard let appState else { return }

        let deferredByModel = appState.modelManager.shouldDeferRecordingStart(
            modelPhase: appState.modelPhase
        )
        let preflight = sessionCoordinator.evaluateStart(
            isRecording: appState.isRecording,
            deferredByModel: deferredByModel,
            needsMicrophone: false,
            needsAccessibility: false
        )

        switch preflight {
        case .alreadyRecording:
            print("[Speex] startRecording BLOCKED — already recording")
            return
        case .deferredByModel:
            if !appState.modelPhase.isActive {
                Task(priority: .utility) { [weak appState] in
                    await appState?.loadModel()
                }
            }
            print("[Speex] startRecording deferred — model loading in background")
            return
        case .readyToStart, .blockedMicrophone, .blockedAccessibility:
            break
        }

        // Recheck permissions each time
        appState.refreshPermissionState()
        let postPermission = sessionCoordinator.evaluateStart(
            isRecording: appState.isRecording,
            deferredByModel: false,
            needsMicrophone: appState.needsMicrophone,
            needsAccessibility: appState.needsAccessibility
        )

        switch postPermission {
        case .blockedMicrophone:
            print("[Speex] ⚠️ startRecording BLOCKED — no microphone permission")
            appState.modelManager.clearQueuedRecordingStart()
            appState.requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        case .blockedAccessibility:
            print("[Speex] ⚠️ startRecording BLOCKED — no accessibility permission")
            appState.modelManager.clearQueuedRecordingStart()
            appState.requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        case .alreadyRecording, .deferredByModel:
            return
        case .readyToStart:
            break
        }

        appState.textInjector?.captureTargetApp()
        appState.refreshInputDevices()

        appState.confirmedText = ""
        appState.partialText = ""
        appState.audioLevel = 0
        sessionCoordinator.beginSession()
        appState.runtimeMetrics.reset()
        appState.transcriptionEngine?.resetSession()
        let resetResult = transcriptionCoordinator.resetSession()
        appState.confirmedText = resetResult.confirmedText
        appState.partialText = resetResult.partialText

        let captureSettings = sessionCoordinator.captureSettings(
            whisperModeEnabled: appState.whisperModeEnabled
        )
        let engine = appState.transcriptionEngine
        let captureStarted = appState.audioEngine?.startCapture(
            inputDeviceUID: appState.inputDeviceUIDForCapture,
            inputGain: captureSettings.inputGain,
            noiseGate: captureSettings.noiseGate,
            onBuffer: { buffer in
                engine?.processAudioBuffer(buffer)
            },
            onLevel: { [weak appState] level in
                Task { @MainActor in
                    appState?.audioLevel = level
                }
            }
        ) ?? false

        guard captureStarted else {
            print("[Speex] ⚠️ startRecording FAILED — audio capture could not start")
            sessionCoordinator.resetSessionState()
            appState.transcriptionEngine?.clearBuffer()
            return
        }

        appState.isRecording = true
        if appState.muteOtherAppsWhileRecording {
            systemAudioMuter.muteSystemAudio()
        }
        appState.modelManager.clearQueuedRecordingStart()
        overlayController.show(appState: appState)
        print("[Speex] ▶ Recording started (mode: \(appState.recordingMode.rawValue), transcription: \(appState.transcriptionMode.rawValue))")
    }

    // MARK: - Stop

    func stopRecording() {
        guard let appState else { return }

        let stopEvaluation = sessionCoordinator.stopSession(
            isRecording: appState.isRecording,
            transcriptionMode: appState.transcriptionMode
        )
        guard case let .stopped(shouldFinalizeOnRelease) = stopEvaluation else { return }
        appState.isRecording = false
        systemAudioMuter.unmuteSystemAudio()
        appState.audioLevel = 0
        overlayController.hide()
        appState.transcriptionEngine?.prepareForFinalize()
        print("[Speex] ⏹ Recording stopped (confirmed: \(appState.confirmedText.count) chars)")

        Task { @MainActor [weak appState, weak self] in
            guard let appState, let self else { return }

            // 1. Grace period — let the AVAudioEngine tap deliver its last
            //    in-flight buffers into the accumulator before tearing down.
            try? await Task.sleep(for: .milliseconds(250))
            appState.audioEngine?.stopCapture()

            // 2. Wait for any chunk that processAccumulatedAudio is currently
            //    transcribing. This ensures its result has been delivered and
            //    confirmedText is up-to-date before the retranscription.
            await appState.transcriptionEngine?.flushProcessing()

            // 3. Yield to let any pending onFinalResult tasks run on the main
            //    actor, so confirmedText reflects the latest chunk results.
            await Task.yield()

            // 4. Finalize: retranscribe the tail of the full session audio and
            //    extract only the new text (delta) not already in confirmedText.
            let currentConfirmedText = appState.confirmedText

            if shouldFinalizeOnRelease {
                appState.transcriptionEngine?.finalize(confirmedText: currentConfirmedText) { [weak appState, weak self] finalText in
                    Task { @MainActor in
                        guard let appState, let self else { return }

                        if let finalText {
                            let result = self.transcriptionCoordinator.consumeFinal(
                                text: finalText,
                                mode: appState.transcriptionMode,
                                confirmedText: appState.confirmedText,
                                recordingStartedAt: self.sessionCoordinator.recordingStartedAt,
                                chunkStartedAt: Date()
                            )
                            appState.confirmedText = result.confirmedText
                            appState.partialText = result.partialText
                        }

                        guard let polished = self.transcriptionCoordinator.finalizedOnReleaseText(
                            confirmedText: appState.confirmedText,
                            partialText: appState.partialText
                        ) else { return }

                        let textToInject = await self.applyAIAutoEditIfEnabled(
                            text: polished,
                            appState: appState
                        )

                        appState.textInjector?.typeText(
                            textToInject,
                            clipboardAfterInjection: textToInject
                        )
                    }
                }
            } else {
                // Streaming mode — when chunks were typed during recording,
                // inject only the finalize delta. When NO text was typed
                // (e.g., short recording with cloud model latency), fall back
                // to the same injection path as on-release for reliability.
                let hadTextDuringRecording = !currentConfirmedText
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                appState.transcriptionEngine?.finalize(confirmedText: currentConfirmedText) { [weak appState, weak self] finalText in
                    Task { @MainActor in
                        guard let appState, let self else { return }

                        // Always process the finalize delta to update confirmedText.
                        if let finalText {
                            let result = self.transcriptionCoordinator.consumeFinal(
                                text: finalText,
                                mode: appState.transcriptionMode,
                                confirmedText: appState.confirmedText,
                                recordingStartedAt: self.sessionCoordinator.recordingStartedAt,
                                chunkStartedAt: Date()
                            )
                            appState.confirmedText = result.confirmedText
                            appState.partialText = result.partialText

                            // Only inject the delta if text was already typed during recording.
                            if hadTextDuringRecording {
                                switch result.action {
                                case .none:
                                    break
                                case let .typeText(text, clipboardAfterInjection):
                                    appState.textInjector?.typeText(text, clipboardAfterInjection: clipboardAfterInjection)
                                case let .copyToClipboard(text):
                                    appState.textInjector?.copyAccumulatedTextToClipboard(text)
                                }
                            }
                        }

                        if hadTextDuringRecording {
                            // Text was injected during recording — AI auto-edit to clipboard.
                            let fullText = appState.confirmedText
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !fullText.isEmpty,
                               appState.aiAutoEditEnabled,
                               let enhancer = appState.aiTextEnhancer
                            {
                                let enhanced = try? await enhancer.enhance(
                                    text: fullText,
                                    language: appState.selectedLanguage
                                )
                                if let enhanced {
                                    appState.textInjector?.copyAccumulatedTextToClipboard(enhanced)
                                    print("[Speex AI] Streaming: enhanced text copied to clipboard")
                                }
                            }
                        } else {
                            // No text was typed during recording — use the same
                            // injection mechanism as on-release (proven to work).
                            guard let polished = self.transcriptionCoordinator.finalizedOnReleaseText(
                                confirmedText: appState.confirmedText,
                                partialText: appState.partialText
                            ) else {
                                print("[Speex] Streaming fallback: no text to inject after finalize")
                                return
                            }

                            let textToInject = await self.applyAIAutoEditIfEnabled(
                                text: polished,
                                appState: appState
                            )

                            // Pre-activate target app from the main thread — the
                            // finalize callback arrives seconds after the overlay
                            // closed, so the target app may need explicit focus.
                            appState.textInjector?.ensureTargetAppActive()
                            try? await Task.sleep(for: .milliseconds(400))

                            print("[Speex] Streaming fallback: injecting \(textToInject.count) chars")
                            appState.textInjector?.typeText(
                                textToInject,
                                clipboardAfterInjection: textToInject
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - AI Auto Edit

    private func applyAIAutoEditIfEnabled(
        text: String,
        appState: AppState
    ) async -> String {
        guard appState.aiAutoEditEnabled,
              let enhancer = appState.aiTextEnhancer
        else { return text }

        do {
            let enhanced = try await enhancer.enhance(
                text: text,
                language: appState.selectedLanguage
            )
            return enhanced
        } catch {
            print("[Speex AI] Enhancement failed, using original: \(error.localizedDescription)")
            return text
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        systemAudioMuter.forceUnmute()
        guard let appState else { return }
        if appState.isRecording {
            appState.audioEngine?.stopCapture()
            appState.isRecording = false
        }
    }
}
