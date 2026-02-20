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
    private var queuedRecordingStartAfterModelReady = false
    private var lastChunkProcessedAt: Date?
    private var recordingStartedAt: Date?
    private var modelWarmupRetryTask: Task<Void, Never>?
    private let permissionService = PermissionService()
    private let editingService = DictationEditingService()

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
                    print("[Wisper] Partial: \(text)")
                    self?.partialText = text
                }
            },
            onFinalResult: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    let chunkStartedAt = Date()

        if self.transcriptionMode == .onRelease,
           let editCommand = TextPostProcessor.editingCommand(in: text)
        {
            if let updated = self.editingService.applyCommand(editCommand, currentText: self.confirmedText) {
                self.confirmedText = updated
                self.textInjector?.copyAccumulatedTextToClipboard(self.confirmedText)
            }
            self.partialText = ""
            self.lastChunkProcessedAt = .now
            return
        }

                    if self.transcriptionMode == .onRelease,
                       let correction = TextPostProcessor.correctionReplacementIfCommand(text)
                    {
                        self.editingService.snapshot(currentText: self.confirmedText)
                        self.confirmedText = TextPostProcessor.replacingLastSentence(
                            in: self.confirmedText,
                            with: correction
                        )
                        self.partialText = ""
                        self.lastChunkProcessedAt = .now
                        let processingMs = Int(Date().timeIntervalSince(chunkStartedAt) * 1000)
                        self.runtimeMetrics.registerChunk(
                            text: correction,
                            processingMs: processingMs,
                            sessionStartedAt: self.recordingStartedAt
                        )
                        return
                    }

                    let separator = TextPostProcessor.separatorForPause(
                        since: self.lastChunkProcessedAt,
                        previousText: self.confirmedText
                    )

                    let polished = TextPostProcessor.processChunk(
                        text,
                        mode: .fluent,
                        isFirstChunk: self.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    guard !polished.isEmpty else { return }

                    let combined = (separator + polished).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !combined.isEmpty else { return }

                    print("[Wisper] Final result: \(combined)")
                    self.editingService.snapshot(currentText: self.confirmedText)
                    self.confirmedText = self.appendChunk(
                        combined,
                        to: self.confirmedText
                    )
                    self.partialText = ""
                    self.lastChunkProcessedAt = .now
                    let processingMs = Int(Date().timeIntervalSince(chunkStartedAt) * 1000)
                    self.runtimeMetrics.registerChunk(
                        text: combined,
                        processingMs: processingMs,
                        sessionStartedAt: self.recordingStartedAt
                    )
                    if self.transcriptionMode == .streaming {
                        self.textInjector?.typeText(
                            combined,
                            clipboardAfterInjection: self.confirmedText
                        )
                    } else {
                        self.textInjector?.copyAccumulatedTextToClipboard(self.confirmedText)
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

        guard modelPhase.isReady else {
            queuedRecordingStartAfterModelReady = true
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
            queuedRecordingStartAfterModelReady = false
            requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard !needsAccessibility else {
            print("[Wisper] ⚠️ startRecording BLOCKED — no accessibility permission")
            queuedRecordingStartAfterModelReady = false
            requestOnboardingPresentation()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        textInjector?.captureTargetApp()
        refreshInputDevices()

        confirmedText = ""
        partialText = ""
        audioLevel = 0
        lastChunkProcessedAt = nil
        recordingStartedAt = .now
        runtimeMetrics.reset()
        editingService.reset()

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
        queuedRecordingStartAfterModelReady = false
        overlayController.show(appState: self)
        print("[Wisper] ▶ Recording started (mode: \(recordingMode.rawValue), transcription: \(transcriptionMode.rawValue))")
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioLevel = 0
        lastChunkProcessedAt = nil
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

                    let confirmed = self.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let partial = self.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let textToInject = !confirmed.isEmpty ? confirmed : partial
                    guard !textToInject.isEmpty else { return }

                    let polished = TextPostProcessor.processFinal(
                        textToInject,
                        mode: .fluent
                    )
                    guard !polished.isEmpty else { return }

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
            modelWarmupRetryTask?.cancel()
            modelWarmupRetryTask = nil

            if queuedRecordingStartAfterModelReady, !isRecording {
                queuedRecordingStartAfterModelReady = false
                startRecording()
            }
            return
        }

        scheduleWarmupRetryIfNeeded()
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
        if !validIDs.contains(selectedModel) {
            selectedModel = Self.defaultBundledModelID
        }
    }

    private func applyBestDownloadedModelAsDefaultIfNeeded() {
        let downloadedModelIDs = Self.downloadedModelIDs()
        guard !downloadedModelIDs.isEmpty else {
            if selectedModel != Self.optionalSuperModelID {
                selectedModel = Self.defaultBundledModelID
            }
            return
        }

        // Respect user preference if their chosen model is already downloaded.
        if downloadedModelIDs.contains(selectedModel) || selectedModel == Self.defaultBundledModelID {
            return
        }

        if let bestDownloaded = Self.modelQualityPriority.first(where: { downloadedModelIDs.contains($0) }) {
            selectedModel = bestDownloaded
            print("[Wisper] ✅ Selected best downloaded model as default: \(bestDownloaded)")
        }
    }

    private static func downloadedModelIDs() -> Set<String> {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }

        let modelsRoot = documentsURL
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)

        return Set(availableModels.compactMap { model in
            let modelFolder = modelsRoot.appendingPathComponent(model.id, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: modelFolder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let hasFiles = ((try? FileManager.default.contentsOfDirectory(atPath: modelFolder.path))?.isEmpty == false)
            return hasFiles ? model.id : nil
        })
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
        guard !isRecording else { return }
        guard !modelPhase.isActive else { return }
        guard !modelPhase.isReady else { return }

        Task(priority: .userInitiated) { [weak self] in
            await self?.loadModel()
        }
    }

    private func scheduleWarmupRetryIfNeeded() {
        guard !isRecording else { return }
        guard modelWarmupRetryTask == nil else { return }

        modelWarmupRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                guard let self else { return }
                self.modelWarmupRetryTask = nil
                self.ensureModelWarmInBackground(reason: "retry_after_error")
            }
        }
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
