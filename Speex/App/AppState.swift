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

    // MARK: - Model State

    @Published var modelPhase: ModelPhase = .idle
    @AppStorage("selectedModel") var selectedModel = ModelManager.defaultBundledModelID

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
    @AppStorage("openaiAPIKey") var openaiAPIKey = ""
    @AppStorage("aiAutoEditEnabled") var aiAutoEditEnabled = false
    @Published private(set) var onboardingPresentationToken = UUID()
    private var hasRunInitialPermissionAudit = false
    private let permissionService = PermissionService()
    private let audioInputSelectionCoordinator = AudioInputSelectionCoordinator()
    let recordingOrchestrator = RecordingOrchestrator()
    let modelManager = ModelManager()
    let updateService = UpdateService()

    // MARK: - Engines

    var audioEngine: AudioEngine?
    var transcriptionEngine: (any TranscriptionProvider)?
    var hotkeyManager: HotkeyManager?
    var textInjector: TextInjector?
    var aiTextEnhancer: (any AITextEnhancerProvider)?

    var isCloudModelConfigured: Bool { !openaiAPIKey.isEmpty }

    init() {
        recordingOrchestrator.appState = self
        TranscriptionEngine.migrateModelsFromDocumentsIfNeeded()
        setupEngines()
        selectedModel = modelManager.normalizeSelectedModel(selectedModel)
        if !ModelManager.isCloudModel(selectedModel) {
            let resolved = modelManager.applyBestDownloaded(currentSelection: selectedModel)
            if selectedModel != resolved {
                selectedModel = resolved
                print("[Speex] Selected model after lifecycle resolution: \(resolved)")
            }
        }
        if hasCompletedOnboarding {
            ensureModelWarmInBackground(reason: "app_init")
        }
    }

    func setupEngines() {
        textInjector = TextInjector()
        audioEngine = AudioEngine()
        refreshInputDevices()
        refreshPermissionState()
        recreateTranscriptionEngine()

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

    // MARK: - Engine Management

    func recreateTranscriptionEngine() {
        let onPartial: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                print("[Speex] Partial: \(text)")
                let result = self.recordingOrchestrator.transcriptionCoordinator.consumePartial(
                    text,
                    confirmedText: self.confirmedText
                )
                self.confirmedText = result.confirmedText
                self.partialText = result.partialText
            }
        }

        let onFinal: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                let chunkStartedAt = Date()
                let result = self.recordingOrchestrator.transcriptionCoordinator.consumeFinal(
                    text: text,
                    mode: self.transcriptionMode,
                    confirmedText: self.confirmedText,
                    recordingStartedAt: self.recordingOrchestrator.recordingStartedAt,
                    chunkStartedAt: chunkStartedAt
                )
                self.confirmedText = result.confirmedText
                self.partialText = result.partialText

                if let metricsText = result.metricsText, let processingMs = result.processingMs {
                    self.runtimeMetrics.registerChunk(
                        text: metricsText,
                        processingMs: processingMs,
                        sessionStartedAt: self.recordingOrchestrator.recordingStartedAt
                    )
                }

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

        if ModelManager.isCloudModel(selectedModel) {
            transcriptionEngine = OpenAITranscriptionEngine(
                apiKey: openaiAPIKey,
                onPartialResult: onPartial,
                onFinalResult: onFinal
            )
        } else {
            transcriptionEngine = TranscriptionEngine(
                onPartialResult: onPartial,
                onFinalResult: onFinal
            )
        }

        refreshAITextEnhancer()
    }

    func refreshAITextEnhancer() {
        if !openaiAPIKey.isEmpty {
            aiTextEnhancer = OpenAITextEnhancer(apiKey: openaiAPIKey)
        } else {
            aiTextEnhancer = nil
        }
    }

    /// Switch between local and cloud engines when the selected model changes.
    func selectModel(_ modelID: String) {
        guard selectedModel != modelID, !isRecording else { return }
        let wasCloud = ModelManager.isCloudModel(selectedModel)
        let willBeCloud = ModelManager.isCloudModel(modelID)

        selectedModel = modelID
        modelPhase = .idle

        if wasCloud != willBeCloud {
            recreateTranscriptionEngine()
        }
    }

    /// Connect to OpenAI cloud with the given API key.
    func connectCloud(apiKey: String) {
        openaiAPIKey = apiKey
        recreateTranscriptionEngine()
        Task { await loadModel() }
    }

    /// Disconnect from OpenAI cloud and switch to the default local model.
    func disconnectCloud() {
        openaiAPIKey = ""
        selectedModel = ModelManager.defaultBundledModelID
        modelPhase = .idle
        recreateTranscriptionEngine()
        reloadModel()
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
        let supportedCodes = Set(LanguageCatalog.availableInterfaceLanguages.map(\.code))
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

    var inputDeviceUIDForCapture: String? {
        audioInputSelectionCoordinator.captureInputDeviceUID(
            selectedDeviceUID: selectedInputDeviceUID,
            availableDevices: availableInputDevices
        )
    }

    func startRecording() { recordingOrchestrator.startRecording() }
    func stopRecording() { recordingOrchestrator.stopRecording() }
    func cleanup() { recordingOrchestrator.cleanup() }

    func loadModel() async {
        guard !modelPhase.isActive else { return }
        modelPhase = .loading(step: L10n.t("model.phase.preparing"))

        let loaded = await modelManager.loadModel(
            engine: transcriptionEngine,
            selectedModel: selectedModel,
            selectedLanguage: selectedLanguage,
            onPhaseChange: { [weak self] phase in
                Task { @MainActor in self?.modelPhase = phase }
            }
        )

        if loaded {
            modelManager.consumeQueuedRecordingStartIfNeeded(
                isRecording: isRecording,
                startRecording: { [weak self] in self?.startRecording() }
            )
            return
        }

        modelManager.scheduleWarmupRetryIfNeeded(
            isRecording: isRecording,
            onRetry: { [weak self] in
                Task { @MainActor in
                    self?.ensureModelWarmInBackground(reason: "retry_after_error")
                }
            }
        )
    }

    func reloadModel() {
        guard !isRecording, !modelPhase.isActive else { return }
        Task { await loadModel() }
    }

    func useDefaultBundledModel() {
        guard selectedModel != ModelManager.defaultBundledModelID else { return }
        selectedModel = ModelManager.defaultBundledModelID
        reloadModel()
    }

    func installAndUseSuperModel() {
        guard !isRecording, !modelPhase.isActive else { return }
        selectedModel = ModelManager.optionalSuperModelID
        Task { await loadModel() }
    }

    func isModelInstalledLocally(_ modelID: String) -> Bool {
        modelManager.isModelInstalledLocally(modelID)
    }

    func ensureModelWarmInBackground(reason _: String) {
        modelManager.ensureModelWarmInBackground(
            isRecording: isRecording,
            modelPhase: modelPhase,
            load: { [weak self] in await self?.loadModel() }
        )
    }

}
