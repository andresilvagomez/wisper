@preconcurrency import AVFoundation
import Combine
import SwiftUI

enum TranscriptionMode: String, CaseIterable {
    case streaming = "Streaming"
    case onRelease = "On Release"

    var localizedTitle: String {
        switch self {
        case .streaming:
            return L10n.t("transcription.mode.streaming")
        case .onRelease:
            return L10n.t("transcription.mode.on_release")
        }
    }
}

enum RecordingMode: String, CaseIterable {
    case pushToTalk = "Push to Talk"
    case toggle = "Toggle"

    var localizedTitle: String {
        switch self {
        case .pushToTalk:
            return L10n.t("recording.mode.push_to_talk")
        case .toggle:
            return L10n.t("recording.mode.toggle")
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    struct RuntimeMetrics {
        var firstTextLatencyMs: Int?
        var lastChunkProcessingMs: Int?
        var averageChunkProcessingMs: Int?
        var chunkCount: Int = 0
        var totalCharacters: Int = 0

        mutating func reset() {
            firstTextLatencyMs = nil
            lastChunkProcessingMs = nil
            averageChunkProcessingMs = nil
            chunkCount = 0
            totalCharacters = 0
        }

        mutating func registerChunk(
            text: String,
            processingMs: Int,
            sessionStartedAt: Date?
        ) {
            chunkCount += 1
            totalCharacters += text.count
            lastChunkProcessingMs = processingMs

            if let sessionStartedAt, firstTextLatencyMs == nil {
                firstTextLatencyMs = Int(Date().timeIntervalSince(sessionStartedAt) * 1000)
            }

            if let currentAverage = averageChunkProcessingMs {
                averageChunkProcessingMs = ((currentAverage * (chunkCount - 1)) + processingMs) / chunkCount
            } else {
                averageChunkProcessingMs = processingMs
            }
        }
    }

    // MARK: - Recording State

    @Published var isRecording = false
    @Published var partialText = ""
    @Published var confirmedText = ""
    @Published var audioLevel: Float = 0
    @Published var runtimeMetrics = RuntimeMetrics()
    @Published var needsAccessibility = false
    @Published var needsMicrophone = false
    @Published var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var availableInputDevices: [AudioInputDevice] = []

    // MARK: - Overlay

    private var overlayController = OverlayWindowController()

    // MARK: - Model State

    @Published var modelPhase: ModelPhase = .idle
    @AppStorage("selectedModel") var selectedModel = defaultBundledModelID

    // MARK: - Settings

    @AppStorage("transcriptionMode") var transcriptionMode: TranscriptionMode = .streaming
    @AppStorage("recordingMode") var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("interfaceLanguage") var interfaceLanguage = "system"
    @AppStorage("selectedLanguage") var selectedLanguage = "auto"
    @AppStorage("whisperModeEnabled") var whisperModeEnabled = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("muteOtherAppsWhileRecording") var muteOtherAppsWhileRecording = false
    @AppStorage("selectedInputDeviceUID") var selectedInputDeviceUID = ""
    @Published private(set) var onboardingPresentationToken = UUID()
    private var hasRunInitialPermissionAudit = false
    private let permissionService = PermissionService()
    private let transcriptionCoordinator = TranscriptionCoordinator()
    private let modelLifecycleCoordinator = ModelLifecycleCoordinator()
    private let recordingSessionCoordinator = RecordingSessionCoordinator()
    private let audioInputSelectionCoordinator = AudioInputSelectionCoordinator()
    let updateService = UpdateService()
    let systemAudioMuter = SystemAudioMuter()

    // MARK: - Engines

    var audioEngine: AudioEngine?
    var transcriptionEngine: TranscriptionEngine?
    var hotkeyManager: HotkeyManager?
    var textInjector: TextInjector?

    // MARK: - Available Languages

    static let availableLanguages: [(code: String, name: String)] = [
        ("auto", "Auto (Detect language)"),
        ("af", "Afrikaans"),
        ("am", "Amharic"),
        ("ar", "العربية"),
        ("as", "Assamese"),
        ("az", "Azerbaijani"),
        ("az-Cyrl", "Azerbaijani (Cyrillic)"),
        ("ba", "Bashkir"),
        ("be", "Belarusian"),
        ("bg", "Български"),
        ("bn", "বাংলা"),
        ("bo", "Tibetan"),
        ("br", "Breton"),
        ("bs", "Bosnian"),
        ("ca", "Català"),
        ("cs", "Čeština"),
        ("cy", "Cymraeg"),
        ("da", "Dansk"),
        ("es", "Español"),
        ("et", "Eesti"),
        ("eu", "Euskara"),
        ("fa", "فارسی"),
        ("fi", "Suomi"),
        ("fo", "Faroese"),
        ("gl", "Galego"),
        ("gu", "ગુજરાતી"),
        ("ha", "Hausa"),
        ("haw", "Hawaiian"),
        ("he", "עברית"),
        ("hi", "हिन्दी"),
        ("hr", "Hrvatski"),
        ("ht", "Haitian Creole"),
        ("hu", "Magyar"),
        ("hy", "Հայերեն"),
        ("id", "Bahasa Indonesia"),
        ("is", "Íslenska"),
        ("jv", "Javanese"),
        ("ka", "ქართული"),
        ("kk", "Қазақ"),
        ("km", "ខ្មែរ"),
        ("kn", "ಕನ್ನಡ"),
        ("la", "Latin"),
        ("lb", "Luxembourgish"),
        ("ln", "Lingala"),
        ("lo", "ລາວ"),
        ("lt", "Lietuvių"),
        ("lv", "Latviešu"),
        ("mg", "Malagasy"),
        ("mi", "Māori"),
        ("mk", "Македонски"),
        ("ml", "മലയാളം"),
        ("mn", "Монгол"),
        ("mr", "मराठी"),
        ("ms", "Bahasa Melayu"),
        ("mt", "Malti"),
        ("my", "မြန်မာ"),
        ("ne", "नेपाली"),
        ("nl", "Nederlands"),
        ("nn", "Nynorsk"),
        ("no", "Norsk"),
        ("oc", "Occitan"),
        ("pa", "ਪੰਜਾਬੀ"),
        ("pl", "Polski"),
        ("ps", "پښتو"),
        ("en", "English"),
        ("en-GB", "English (UK)"),
        ("en-US", "English (US)"),
        ("pt", "Português"),
        ("pt-BR", "Português (Brasil)"),
        ("pt-PT", "Português (Portugal)"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("ro", "Română"),
        ("ru", "Русский"),
        ("sa", "Sanskrit"),
        ("sd", "Sindhi"),
        ("si", "සිංහල"),
        ("sk", "Slovenčina"),
        ("sl", "Slovenščina"),
        ("sn", "Shona"),
        ("so", "Soomaali"),
        ("sq", "Shqip"),
        ("sr", "Српски"),
        ("su", "Sundanese"),
        ("sv", "Svenska"),
        ("sw", "Kiswahili"),
        ("ta", "தமிழ்"),
        ("te", "తెలుగు"),
        ("tg", "Тоҷикӣ"),
        ("th", "ไทย"),
        ("tk", "Türkmen"),
        ("tl", "Tagalog"),
        ("tr", "Türkçe"),
        ("tt", "Татар"),
        ("uk", "Українська"),
        ("ur", "اردو"),
        ("uz", "Oʻzbek"),
        ("vi", "Tiếng Việt"),
        ("yi", "ייִדיש"),
        ("yo", "Yorùbá"),
        ("yue", "粵語"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("zh-Hans", "中文（简体）"),
        ("zh-Hant", "中文（繁體）"),
        ("zh", "中文"),
    ]

    static let availableInterfaceLanguages: [(code: String, name: String)] = [
        ("system", "System"),
        ("es", "Español"),
        ("en", "English"),
        ("pt", "Português"),
        ("fr", "Français"),
        ("de", "Deutsch"),
    ]

    static let defaultBundledModelID = "openai_whisper-large-v3-v20240930_turbo"
    static let optionalSuperModelID = "openai_whisper-large-v3-v20240930"

    static let availableModels: [(id: String, name: String, size: String)] = [
        (defaultBundledModelID, "Speex Turbo (Predeterminado)", "~632 MB"),
        (optionalSuperModelID, "Speex Super Pro", "~1.5 GB"),
    ]

    /// Priority from highest quality to lowest quality.
    static let modelQualityPriority: [String] = [
        optionalSuperModelID,
        defaultBundledModelID,
    ]

    init() {
        TranscriptionEngine.migrateModelsFromDocumentsIfNeeded()
        setupEngines()
        normalizeSelectedModelIfNeeded()
        applyBestDownloadedModelAsDefaultIfNeeded()
        if hasCompletedOnboarding {
            ensureModelWarmInBackground(reason: "app_init")
        }
    }

    func setupEngines() {
        textInjector = TextInjector()
        audioEngine = AudioEngine()
        refreshInputDevices()
        refreshPermissionState()

        transcriptionEngine = TranscriptionEngine(
            onPartialResult: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    print("[Speex] Partial: \(text)")
                    let result = self.transcriptionCoordinator.consumePartial(
                        text,
                        confirmedText: self.confirmedText
                    )
                    self.confirmedText = result.confirmedText
                    self.partialText = result.partialText
                }
            },
            onFinalResult: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    let chunkStartedAt = Date()
                    let result = self.transcriptionCoordinator.consumeFinal(
                        text: text,
                        mode: self.transcriptionMode,
                        confirmedText: self.confirmedText,
                        recordingStartedAt: self.recordingSessionCoordinator.recordingStartedAt,
                        chunkStartedAt: chunkStartedAt
                    )
                    self.confirmedText = result.confirmedText
                    self.partialText = result.partialText

                    if let metricsText = result.metricsText, let processingMs = result.processingMs {
                        self.runtimeMetrics.registerChunk(
                            text: metricsText,
                            processingMs: processingMs,
                            sessionStartedAt: self.recordingSessionCoordinator.recordingStartedAt
                        )
                    }

                    // Skip injection if recording already stopped — finalize() handles the rest.
                    // We still update confirmedText/partialText above so finalize computes the correct delta.
                    guard self.isRecording else { return }

                    switch result.action {
                    case .none:
                        break
                    case let .typeText(text, clipboardAfterInjection):
                        print("[Speex] Final result: \(text)")
                        self.textInjector?.typeText(
                            text,
                            clipboardAfterInjection: clipboardAfterInjection
                        )
                    case let .copyToClipboard(text):
                        self.textInjector?.copyAccumulatedTextToClipboard(text)
                    }
                }
            }
        )

        hotkeyManager = HotkeyManager(
            onKeyDown: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.recordingMode == .pushToTalk {
                        self.startRecording()
                    } else {
                        self.toggleRecording()
                    }
                }
            },
            onKeyUp: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.recordingMode == .pushToTalk {
                        self.stopRecording()
                    }
                }
            }
        )
    }

    func refreshPermissionState(
        requestAccessibilityPrompt: Bool = false,
        requestMicrophonePrompt: Bool = false
    ) {
        let state = permissionService.refreshState(
            accessibilityProvider: textInjector,
            requestAccessibilityPrompt: requestAccessibilityPrompt
        )
        needsAccessibility = state.needsAccessibility
        microphonePermissionStatus = state.microphoneStatus
        needsMicrophone = state.needsMicrophone
        print("[Speex] Microphone permission: \(state.microphoneStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        if needsAccessibility || needsMicrophone {
            hasCompletedOnboarding = false
        }

        if requestMicrophonePrompt, state.microphoneStatus == .notDetermined {
            Task {
                let requested = await permissionService.requestMicrophonePermissionIfNeeded()
                await MainActor.run {
                    self.needsMicrophone = requested.needsMicrophone
                    self.microphonePermissionStatus = requested.microphoneStatus
                    print("[Speex] Microphone permission granted: \(!requested.needsMicrophone)")
                }
            }
        }
    }

    func runInitialPermissionAuditIfNeeded() async {
        guard !hasRunInitialPermissionAudit else { return }
        hasRunInitialPermissionAudit = true

        refreshPermissionState(
            requestAccessibilityPrompt: true,
            requestMicrophonePrompt: true
        )

        try? await Task.sleep(for: .milliseconds(350))
        refreshPermissionState()

        if needsAccessibility || needsMicrophone {
            requestOnboardingPresentation()
        }

        if hasCompletedOnboarding {
            ensureModelWarmInBackground(reason: "permission_audit")
        }
    }

    func requestOnboardingPresentation() {
        hasCompletedOnboarding = false
        onboardingPresentationToken = UUID()
    }

    func requestMicrophonePermission() async {
        let status = permissionService.refreshState(
            accessibilityProvider: textInjector,
            requestAccessibilityPrompt: false
        ).microphoneStatus
        if status == .notDetermined {
            let requested = await permissionService.requestMicrophonePermissionIfNeeded()
            needsMicrophone = requested.needsMicrophone
            microphonePermissionStatus = requested.microphoneStatus
            print("[Speex] Microphone permission granted: \(!requested.needsMicrophone)")
            return
        }

        refreshPermissionState()
        if status == .denied || status == .restricted {
            openSystemSettings(.microphone)
        }
    }

    func openSystemSettings(_ permission: SystemPermission) {
        guard let url = permissionService.settingsURL(for: permission) else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    var hasMultipleInputDevices: Bool {
        availableInputDevices.count > 1
    }

    var selectedInputDeviceName: String {
        audioInputSelectionCoordinator.selectedInputDeviceName(
            selectedDeviceUID: selectedInputDeviceUID,
            availableDevices: availableInputDevices,
            fallbackName: L10n.t("audio.input.fallback")
        )
    }

    var resolvedInterfaceLanguageCode: String {
        if interfaceLanguage != "system" { return interfaceLanguage }

        let preferred = Locale.preferredLanguages.first ?? "en"
        let preferredCode = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        let supportedCodes = Set(Self.availableInterfaceLanguages.map(\.code))
        return supportedCodes.contains(preferredCode) ? preferredCode : "en"
    }

    func refreshInputDevices() {
        let result = audioInputSelectionCoordinator.resolveSelection(
            devices: AudioEngine.availableInputDevices(),
            currentSelection: selectedInputDeviceUID,
            defaultDeviceUID: AudioEngine.defaultInputDeviceUID()
        )
        availableInputDevices = result.availableDevices
        selectedInputDeviceUID = result.selectedDeviceUID
    }

    private var inputDeviceUIDForCapture: String? {
        audioInputSelectionCoordinator.captureInputDeviceUID(
            selectedDeviceUID: selectedInputDeviceUID,
            availableDevices: availableInputDevices
        )
    }

    func startRecording() {
        let deferredByModel = modelLifecycleCoordinator.shouldDeferRecordingStart(modelPhase: modelPhase)
        let preflight = recordingSessionCoordinator.evaluateStart(
            isRecording: isRecording,
            deferredByModel: deferredByModel,
            needsMicrophone: false,
            needsAccessibility: false
        )

        switch preflight {
        case .alreadyRecording:
            print("[Speex] startRecording BLOCKED — already recording")
            return
        case .deferredByModel:
            if !modelPhase.isActive {
                Task(priority: .utility) { [weak self] in
                    await self?.loadModel()
                }
            }
            print("[Speex] startRecording deferred — model loading in background")
            return
        case .readyToStart, .blockedMicrophone, .blockedAccessibility:
            break
        }

        // Recheck permissions each time
        refreshPermissionState()
        let postPermission = recordingSessionCoordinator.evaluateStart(
            isRecording: isRecording,
            deferredByModel: false,
            needsMicrophone: needsMicrophone,
            needsAccessibility: needsAccessibility
        )

        switch postPermission {
        case .blockedMicrophone:
            print("[Speex] ⚠️ startRecording BLOCKED — no microphone permission")
            modelLifecycleCoordinator.clearQueuedRecordingStart()
            requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        case .blockedAccessibility:
            print("[Speex] ⚠️ startRecording BLOCKED — no accessibility permission")
            modelLifecycleCoordinator.clearQueuedRecordingStart()
            requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        case .alreadyRecording, .deferredByModel:
            return
        case .readyToStart:
            break
        }

        textInjector?.captureTargetApp()
        refreshInputDevices()

        confirmedText = ""
        partialText = ""
        audioLevel = 0
        recordingSessionCoordinator.beginSession()
        runtimeMetrics.reset()
        transcriptionEngine?.resetSession()
        let resetResult = transcriptionCoordinator.resetSession()
        confirmedText = resetResult.confirmedText
        partialText = resetResult.partialText

        let captureSettings = recordingSessionCoordinator.captureSettings(
            whisperModeEnabled: whisperModeEnabled
        )
        let engine = transcriptionEngine
        let captureStarted = audioEngine?.startCapture(
            inputDeviceUID: inputDeviceUIDForCapture,
            inputGain: captureSettings.inputGain,
            noiseGate: captureSettings.noiseGate,
            onBuffer: { buffer in
                engine?.processAudioBuffer(buffer)
            },
            onLevel: { [weak self] level in
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }
        ) ?? false

        guard captureStarted else {
            print("[Speex] ⚠️ startRecording FAILED — audio capture could not start")
            recordingSessionCoordinator.resetSessionState()
            transcriptionEngine?.clearBuffer()
            return
        }

        isRecording = true
        if muteOtherAppsWhileRecording {
            systemAudioMuter.muteSystemAudio()
        }
        modelLifecycleCoordinator.clearQueuedRecordingStart()
        overlayController.show(appState: self)
        print("[Speex] ▶ Recording started (mode: \(recordingMode.rawValue), transcription: \(transcriptionMode.rawValue))")
    }

    func stopRecording() {
        let stopEvaluation = recordingSessionCoordinator.stopSession(
            isRecording: isRecording,
            transcriptionMode: transcriptionMode
        )
        guard case let .stopped(shouldFinalizeOnRelease) = stopEvaluation else { return }
        isRecording = false
        systemAudioMuter.unmuteSystemAudio()
        audioLevel = 0
        overlayController.hide()
        transcriptionEngine?.prepareForFinalize()
        print("[Speex] ⏹ Recording stopped (confirmed: \(confirmedText.count) chars)")

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Grace period — let the AVAudioEngine tap deliver its last
            //    in-flight buffers into the accumulator before tearing down.
            try? await Task.sleep(for: .milliseconds(250))
            self.audioEngine?.stopCapture()

            // 2. Wait for any chunk that processAccumulatedAudio is currently
            //    transcribing. This ensures its result has been delivered and
            //    confirmedText is up-to-date before the retranscription.
            await self.transcriptionEngine?.flushProcessing()

            // 3. Finalize: retranscribe the tail of the full session audio and
            //    extract only the new text (delta) not already in confirmedText.
            let currentConfirmedText = self.confirmedText

            if shouldFinalizeOnRelease {
                self.transcriptionEngine?.finalize(confirmedText: currentConfirmedText) { [weak self] finalText in
                    Task { @MainActor in
                        guard let self else { return }

                        if let finalText {
                            let result = self.transcriptionCoordinator.consumeFinal(
                                text: finalText,
                                mode: self.transcriptionMode,
                                confirmedText: self.confirmedText,
                                recordingStartedAt: self.recordingSessionCoordinator.recordingStartedAt,
                                chunkStartedAt: Date()
                            )
                            self.confirmedText = result.confirmedText
                            self.partialText = result.partialText
                        }

                        guard let polished = self.transcriptionCoordinator.finalizedOnReleaseText(
                            confirmedText: self.confirmedText,
                            partialText: self.partialText
                        ) else { return }

                        self.textInjector?.typeText(
                            polished,
                            clipboardAfterInjection: polished
                        )
                    }
                }
            } else {
                // Streaming mode — use completion to inject the delta directly.
                self.transcriptionEngine?.finalize(confirmedText: currentConfirmedText) { [weak self] finalText in
                    Task { @MainActor in
                        guard let self, let finalText else { return }

                        let result = self.transcriptionCoordinator.consumeFinal(
                            text: finalText,
                            mode: self.transcriptionMode,
                            confirmedText: self.confirmedText,
                            recordingStartedAt: self.recordingSessionCoordinator.recordingStartedAt,
                            chunkStartedAt: Date()
                        )
                        self.confirmedText = result.confirmedText
                        self.partialText = result.partialText

                        switch result.action {
                        case .none:
                            break
                        case let .typeText(text, clipboardAfterInjection):
                            self.textInjector?.typeText(text, clipboardAfterInjection: clipboardAfterInjection)
                        case let .copyToClipboard(text):
                            self.textInjector?.copyAccumulatedTextToClipboard(text)
                        }
                    }
                }
            }
        }
    }

    func cleanup() {
        systemAudioMuter.forceUnmute()
        if isRecording {
            audioEngine?.stopCapture()
            isRecording = false
        }
    }

    func loadModel() async {
        guard !modelPhase.isActive else { return }

        modelPhase = .loading(step: L10n.t("model.phase.preparing"))

        let engine = transcriptionEngine
        let model = selectedModel
        let lang = selectedLanguage == "auto" ? nil : Self.normalizeWhisperLanguageCode(selectedLanguage)

        let phaseHandler: @Sendable (ModelPhase) -> Void = { [weak self] phase in
            Task { @MainActor in
                self?.modelPhase = phase
            }
        }

        let loaded = await Task.detached(priority: .utility) {
            await engine?.loadModel(
                modelName: model,
                language: lang,
                onPhaseChange: phaseHandler,
                eagerWarmup: true
            ) ?? false
        }.value

        if loaded {
            modelLifecycleCoordinator.consumeQueuedRecordingStartIfNeeded(
                isRecording: isRecording,
                startRecording: { [weak self] in self?.startRecording() }
            )
            return
        }

        modelLifecycleCoordinator.scheduleWarmupRetryIfNeeded(
            isRecording: isRecording,
            onRetry: { [weak self] in
                self?.ensureModelWarmInBackground(reason: "retry_after_error")
            }
        )
    }

    func reloadModel() {
        guard !isRecording, !modelPhase.isActive else { return }
        Task { await loadModel() }
    }

    func useDefaultBundledModel() {
        guard selectedModel != Self.defaultBundledModelID else { return }
        selectedModel = Self.defaultBundledModelID
        reloadModel()
    }

    func installAndUseSuperModel() {
        guard !isRecording, !modelPhase.isActive else { return }
        selectedModel = Self.optionalSuperModelID
        Task { await loadModel() }
    }

    func isModelInstalledLocally(_ modelID: String) -> Bool {
        TranscriptionEngine.isModelBundled(modelID) || TranscriptionEngine.isModelDownloaded(modelID)
    }

    private func normalizeSelectedModelIfNeeded() {
        let validIDs = Set(Self.availableModels.map(\.id))
        selectedModel = modelLifecycleCoordinator.normalizedSelectedModel(
            selectedModel: selectedModel,
            validModelIDs: validIDs,
            defaultModelID: Self.defaultBundledModelID
        )
    }

    private func applyBestDownloadedModelAsDefaultIfNeeded() {
        let downloadedModelIDs = modelLifecycleCoordinator.downloadedModelIDs(
            availableModelIDs: Self.availableModels.map(\.id)
        )
        let resolved = modelLifecycleCoordinator.resolvedModelSelection(
            currentSelection: selectedModel,
            downloadedModelIDs: downloadedModelIDs,
            defaultModelID: Self.defaultBundledModelID,
            qualityPriority: Self.modelQualityPriority
        )

        if selectedModel != resolved {
            selectedModel = resolved
            print("[Speex] ✅ Selected model after lifecycle resolution: \(resolved)")
        }
    }

    static func normalizeWhisperLanguageCode(_ code: String) -> String {
        switch code.lowercased() {
        case "pt-br", "pt-pt":
            return "pt"
        case "en-gb", "en-us":
            return "en"
        case "zh-hans", "zh-hant":
            return "zh"
        case "az-cyrl":
            return "az"
        default:
            return code
        }
    }

    func ensureModelWarmInBackground(reason _: String) {
        modelLifecycleCoordinator.ensureModelWarmInBackground(
            isRecording: isRecording,
            modelPhase: modelPhase,
            load: { [weak self] in
                await self?.loadModel()
            }
        )
    }

}
