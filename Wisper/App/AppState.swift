@preconcurrency import AVFoundation
import Combine
import SwiftUI

enum TranscriptionMode: String, CaseIterable {
    case streaming = "Streaming"
    case onRelease = "On Release"
}

enum RecordingMode: String, CaseIterable {
    case pushToTalk = "Push to Talk"
    case toggle = "Toggle"
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Recording State

    @Published var isRecording = false
    @Published var partialText = ""
    @Published var confirmedText = ""
    @Published var audioLevel: Float = 0
    @Published var needsAccessibility = false
    @Published var needsMicrophone = false
    @Published var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var availableInputDevices: [AudioInputDevice] = []

    // MARK: - Overlay

    private var overlayController = OverlayWindowController()

    // MARK: - Model State

    @Published var modelPhase: ModelPhase = .idle
    @Published var selectedModel = "openai_whisper-base"

    // MARK: - Settings

    @AppStorage("transcriptionMode") var transcriptionMode: TranscriptionMode = .streaming
    @AppStorage("recordingMode") var recordingMode: RecordingMode = .pushToTalk
    @AppStorage("selectedLanguage") var selectedLanguage = "es"
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("selectedInputDeviceUID") var selectedInputDeviceUID = ""

    // MARK: - Engines

    var audioEngine: AudioEngine?
    var transcriptionEngine: TranscriptionEngine?
    var hotkeyManager: HotkeyManager?
    var textInjector: TextInjector?

    // MARK: - Available Languages

    static let availableLanguages: [(code: String, name: String)] = [
        ("es", "Español"),
        ("en", "English"),
        ("pt", "Português"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("zh", "中文"),
    ]

    static let availableModels: [(id: String, name: String, size: String)] = [
        ("openai_whisper-base", "Base (Fast, good for testing)", "~80 MB"),
        ("openai_whisper-small", "Small (Balanced)", "~216 MB"),
        ("openai_whisper-large-v3-v20240930_turbo", "Large V3 Turbo (Best)", "~632 MB"),
        ("openai_whisper-large-v3-v20240930", "Large V3 (Highest quality)", "~1.5 GB"),
    ]

    init() {
        setupEngines()
        Task { [weak self] in
            await self?.loadModel()
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
                    print("[Wisper] Partial: \(text)")
                    self?.partialText = text
                }
            },
            onFinalResult: { [weak self] text in
                Task { @MainActor in
                    guard let self else { return }
                    print("[Wisper] Final result: \(text)")
                    self.confirmedText += text + " "
                    self.partialText = ""
                    if self.transcriptionMode == .streaming {
                        self.textInjector?.typeText(text)
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
        if requestAccessibilityPrompt {
            textInjector?.setup()
        } else {
            textInjector?.recheckAccessibility()
        }
        needsAccessibility = !(textInjector?.hasAccessibility ?? false)

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphonePermissionStatus = micStatus
        needsMicrophone = (micStatus != .authorized)
        print("[Wisper] Microphone permission: \(micStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        if requestMicrophonePrompt, micStatus == .notDetermined {
            Task {
                let granted = await AudioEngine.requestPermission()
                await MainActor.run {
                    self.needsMicrophone = !granted
                    self.microphonePermissionStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .audio)
                    print("[Wisper] Microphone permission granted: \(granted)")
                }
            }
        }
    }

    func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            let granted = await AudioEngine.requestPermission()
            needsMicrophone = !granted
            microphonePermissionStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .audio)
            print("[Wisper] Microphone permission granted: \(granted)")
            return
        }

        refreshPermissionState()
        if status == .denied || status == .restricted {
            openSystemSettings(.microphone)
        }
    }

    enum SystemPermission {
        case accessibility
        case microphone
    }

    func openSystemSettings(_ permission: SystemPermission) {
        let urlString: String
        switch permission {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }

        guard let url = URL(string: urlString) else { return }
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
            ?? "Micrófono"
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
        guard modelPhase.isReady, !isRecording else {
            print("[Wisper] startRecording BLOCKED — modelReady=\(modelPhase.isReady) isRecording=\(isRecording)")
            return
        }

        // Recheck permissions each time
        refreshPermissionState()
        guard !needsMicrophone else {
            print("[Wisper] ⚠️ startRecording BLOCKED — no microphone permission")
            return
        }

        textInjector?.captureTargetApp()
        refreshInputDevices()

        confirmedText = ""
        partialText = ""
        audioLevel = 0

        let engine = transcriptionEngine
        let captureStarted = audioEngine?.startCapture(
            inputDeviceUID: inputDeviceUIDForCapture,
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
        overlayController.show(appState: self)
        print("[Wisper] ▶ Recording started (mode: \(recordingMode.rawValue), transcription: \(transcriptionMode.rawValue))")
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        audioLevel = 0
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
                    self.textInjector?.typeText(textToInject)
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

        modelPhase = .loading(step: "Preparing model...")

        let engine = transcriptionEngine
        let model = selectedModel
        let lang = selectedLanguage

        let phaseHandler: @Sendable (ModelPhase) -> Void = { [weak self] phase in
            Task { @MainActor in
                self?.modelPhase = phase
            }
        }

        _ = await engine?.loadModel(
            modelName: model,
            language: lang,
            onPhaseChange: phaseHandler
        ) ?? false
    }

    func reloadModel() {
        guard !isRecording, !modelPhase.isActive else { return }
        Task { await loadModel() }
    }
}
