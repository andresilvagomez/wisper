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
    @AppStorage("selectedInputDeviceUID") var selectedInputDeviceUID = ""
    @Published private(set) var onboardingPresentationToken = UUID()
    private var hasRunInitialPermissionAudit = false
    private var recordingStartedAt: Date?
    private let permissionService = PermissionService()
    private let transcriptionCoordinator = TranscriptionCoordinator()
    private let modelLifecycleCoordinator = ModelLifecycleCoordinator()

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
        (defaultBundledModelID, "Whisper Turbo (Predeterminado)", "~632 MB"),
        (optionalSuperModelID, "Whisper Super Pro", "~1.5 GB"),
    ]

    /// Priority from highest quality to lowest quality.
    static let modelQualityPriority: [String] = [
        optionalSuperModelID,
        defaultBundledModelID,
    ]

    init() {
        setupEngines()
        normalizeSelectedModelIfNeeded()
        applyBestDownloadedModelAsDefaultIfNeeded()
        ensureModelWarmInBackground(reason: "app_init")
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
                    print("[Wisper] Partial: \(text)")
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
                        recordingStartedAt: self.recordingStartedAt,
                        chunkStartedAt: chunkStartedAt
                    )
                    self.confirmedText = result.confirmedText
                    self.partialText = result.partialText

                    if let metricsText = result.metricsText, let processingMs = result.processingMs {
                        self.runtimeMetrics.registerChunk(
                            text: metricsText,
                            processingMs: processingMs,
                            sessionStartedAt: self.recordingStartedAt
                        )
                    }

                    switch result.action {
                    case .none:
                        break
                    case let .typeText(text, clipboardAfterInjection):
                        print("[Wisper] Final result: \(text)")
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
        print("[Wisper] Microphone permission: \(state.microphoneStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        if needsAccessibility || needsMicrophone {
            hasCompletedOnboarding = false
        }

        if requestMicrophonePrompt, state.microphoneStatus == .notDetermined {
            Task {
                let requested = await permissionService.requestMicrophonePermissionIfNeeded()
                await MainActor.run {
                    self.needsMicrophone = requested.needsMicrophone
                    self.microphonePermissionStatus = requested.microphoneStatus
                    print("[Wisper] Microphone permission granted: \(!requested.needsMicrophone)")
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

        ensureModelWarmInBackground(reason: "permission_audit")
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
            print("[Wisper] Microphone permission granted: \(!requested.needsMicrophone)")
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
        availableInputDevices.first(where: { $0.id == selectedInputDeviceUID })?.name
            ?? availableInputDevices.first?.name
            ?? L10n.t("audio.input.fallback")
    }

    var resolvedInterfaceLanguageCode: String {
        if interfaceLanguage != "system" { return interfaceLanguage }

        let preferred = Locale.preferredLanguages.first ?? "en"
        let preferredCode = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        let supportedCodes = Set(Self.availableInterfaceLanguages.map(\.code))
        return supportedCodes.contains(preferredCode) ? preferredCode : "en"
    }

    func refreshInputDevices() {
        let devices = AudioEngine.availableInputDevices()
        availableInputDevices = devices

        guard !devices.isEmpty else {
            selectedInputDeviceUID = ""
            return
        }

        if devices.count == 1 {
            selectedInputDeviceUID = devices[0].id
            return
        }

        if devices.contains(where: { $0.id == selectedInputDeviceUID }) {
            return
        }

        if let defaultUID = AudioEngine.defaultInputDeviceUID(),
           devices.contains(where: { $0.id == defaultUID }) {
            selectedInputDeviceUID = defaultUID
        } else {
            selectedInputDeviceUID = devices[0].id
        }
    }

    private var inputDeviceUIDForCapture: String? {
        guard !selectedInputDeviceUID.isEmpty else { return nil }
        guard availableInputDevices.contains(where: { $0.id == selectedInputDeviceUID }) else { return nil }
        return selectedInputDeviceUID
    }

    func startRecording() {
        guard !isRecording else {
            print("[Wisper] startRecording BLOCKED — already recording")
            return
        }

        guard !modelLifecycleCoordinator.shouldDeferRecordingStart(modelPhase: modelPhase) else {
            if !modelPhase.isActive {
                Task(priority: .utility) { [weak self] in
                    await self?.loadModel()
                }
            }
            print("[Wisper] startRecording deferred — model loading in background")
            return
        }

        // Recheck permissions each time
        refreshPermissionState()
        guard !needsMicrophone else {
            print("[Wisper] ⚠️ startRecording BLOCKED — no microphone permission")
            modelLifecycleCoordinator.clearQueuedRecordingStart()
            requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard !needsAccessibility else {
            print("[Wisper] ⚠️ startRecording BLOCKED — no accessibility permission")
            modelLifecycleCoordinator.clearQueuedRecordingStart()
            requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        textInjector?.captureTargetApp()
        refreshInputDevices()

        confirmedText = ""
        partialText = ""
        audioLevel = 0
        recordingStartedAt = .now
        runtimeMetrics.reset()
        let resetResult = transcriptionCoordinator.resetSession()
        confirmedText = resetResult.confirmedText
        partialText = resetResult.partialText

        let engine = transcriptionEngine
        let captureStarted = audioEngine?.startCapture(
            inputDeviceUID: inputDeviceUIDForCapture,
            inputGain: whisperModeEnabled ? 2.2 : 1.0,
            noiseGate: whisperModeEnabled ? 0.004 : 0,
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
            print("[Wisper] ⚠️ startRecording FAILED — audio capture could not start")
            transcriptionEngine?.clearBuffer()
            return
        }

        isRecording = true
        modelLifecycleCoordinator.clearQueuedRecordingStart()
        overlayController.show(appState: self)
        print("[Wisper] ▶ Recording started (mode: \(recordingMode.rawValue), transcription: \(transcriptionMode.rawValue))")
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioLevel = 0
        recordingStartedAt = nil
        audioEngine?.stopCapture()
        overlayController.hide()
        print("[Wisper] ⏹ Recording stopped (confirmed: \(confirmedText.count) chars)")

        if transcriptionMode == .onRelease {
            transcriptionEngine?.finalize { [weak self] in
                Task { @MainActor in
                    guard let self else { return }

                    for _ in 0..<12 {
                        if !self.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                        try? await Task.sleep(for: .milliseconds(50))
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
            transcriptionEngine?.finalize()
        }
    }

    func cleanup() {
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
                onPhaseChange: phaseHandler
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
            print("[Wisper] ✅ Selected model after lifecycle resolution: \(resolved)")
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
