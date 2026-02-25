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

            // 3. Finalize: retranscribe the tail of the full session audio and
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
                // Streaming mode — use completion to inject the delta directly.
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

                            switch result.action {
                            case .none:
                                break
                            case let .typeText(text, clipboardAfterInjection):
                                appState.textInjector?.typeText(text, clipboardAfterInjection: clipboardAfterInjection)
                            case let .copyToClipboard(text):
                                appState.textInjector?.copyAccumulatedTextToClipboard(text)
                            }
                        }

                        // In streaming mode, AI auto-edit enhances the full text
                        // and copies it to clipboard for the user to paste if desired.
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
