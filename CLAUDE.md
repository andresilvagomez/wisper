# Wisper

macOS menu bar app for on-device speech-to-text using WhisperKit. Press ⌥Space to record, text gets pasted where the cursor is.

## Architecture

```
WisperApp (SwiftUI @main, MenuBarExtra)
  └─ AppState (@MainActor, central state)
       ├─ AudioEngine        → Microphone capture (16kHz mono PCM)
       ├─ TranscriptionEngine → WhisperKit ML inference
       ├─ HotkeyManager       → Global ⌥Space shortcut
       ├─ TextInjector         → Clipboard + CGEvent Cmd+V paste
       └─ OverlayWindowController → Floating recording indicator
```

## Project Structure

```
Wisper/
├── App/
│   ├── WisperApp.swift          # @main entry, MenuBarExtra + Settings + Onboarding scenes
│   ├── AppState.swift           # Central state: recording, model loading, engines init
│   └── ModelPhase.swift         # Enum: idle → downloading → loading → ready | error
├── Audio/
│   └── AudioEngine.swift        # AVAudioEngine mic capture, format conversion, RMS levels
├── Transcription/
│   └── TranscriptionEngine.swift # WhisperKit transcription, 3s chunks, hallucination filter
├── Input/
│   ├── HotkeyManager.swift      # Global hotkey (⌥Space) via HotKey library
│   └── TextInjector.swift       # Paste text into target app via CGEvent Cmd+V
├── UI/
│   ├── MenuBarView.swift        # Menu bar dropdown: status, transcription, language, settings
│   ├── TranscriptionOverlay.swift # FloatingPanel with audio wave bars + stop button
│   ├── OnboardingView.swift     # 3-step setup wizard (welcome, permissions, model)
│   └── SettingsView.swift       # Tabs: General, Model, About
└── Resources/
    ├── Info.plist               # LSUIElement=true, usage descriptions
    └── Wisper.entitlements      # audio-input + automation.apple-events
WisperTests/
├── HallucinationFilterTests.swift  # Tests for whisper hallucination filtering
├── TextInjectorTests.swift         # Tests for text injection logic
└── ModelPhaseTests.swift           # Tests for model phase state machine
```

## Build System

- **XcodeGen** — project generated from `project.yml`, run `xcodegen generate` after changes
- **Swift 6.0**, macOS 14.0+ deployment target
- **Bundle ID**: `com.andresilvagomez.wisper`

### Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 0.12.0+ | On-device Whisper inference via CoreML |
| [HotKey](https://github.com/soffes/HotKey) | 0.2.1+ | System-wide hotkey registration |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 2.2.0+ | Keyboard shortcut UI components |

### Build & Run

```bash
xcodegen generate
# Then open Wisper.xcodeproj in Xcode and ⌘R
# Or from CLI (requires Xcode, not just CommandLineTools):
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Wisper -configuration Debug build
```

### Code Signing

- `CODE_SIGN_STYLE: Manual` with Apple Development certificate (SHA: `DD9A14A7890D716B95CFACB96F0EBDA356EE18CB`)
- `DEVELOPMENT_TEAM: 7NBJJ9P97F` → stable `TeamIdentifier=AK72336HUE`
- `ENABLE_HARDENED_RUNTIME: false` — required for CGEvent paste
- `ENABLE_APP_SANDBOX: false` — sandbox blocks network + CGEvent
- **Important**: Ad-hoc signing creates new cdhash each rebuild → TCC revokes Accessibility. Manual signing with Apple Development cert keeps stable TeamIdentifier across rebuilds.

### Tests

```bash
# Run unit tests (26 tests across 3 suites)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme WisperTests -configuration Debug test -destination 'platform=macOS'
```

Test suites: `HallucinationFilterTests`, `TextInjectorTests`, `ModelPhaseTests`

## Key Concepts

### Text Injection (Paste)

The app transcribes speech and pastes text into the user's active app. Two methods:

1. **AXUIElement** (primary): Directly sets `kAXSelectedTextAttribute` on focused element — inserts at cursor
2. **Clipboard + CGEvent Cmd+V** (fallback): Copies to pasteboard, simulates ⌘V keystroke

**Requirements**:
- macOS Accessibility permission (System Settings → Privacy → Accessibility)
- `AXIsProcessTrusted()` must return `true`
- macOS Microphone permission (System Settings → Privacy → Microphone)

**Permission checks**:
- `setup()` triggers native Accessibility prompt via `AXIsProcessTrustedWithOptions`
- `startRecording()` rechecks both Accessibility and Microphone before each recording
- UI shows warnings in MenuBarView when permissions are missing

**Flow**: `captureTargetApp()` → record → transcribe → `typeText()` → AXUIElement or clipboard+Cmd+V

### Whisper Hallucination Filter

WhisperKit produces false positives on silence/noise. `TranscriptionEngine.isHallucination()` filters:
- Sound tags: `[música]`, `[music]`, `[applause]`, `[silence]`, etc.
- Common phrases: "gracias por ver", "thanks for watching", "subscribe"
- Bracketed/parenthesized text: `[anything]`, `(anything)`
- Pure punctuation, text < 3 chars

### Recording Overlay

`TranscriptionOverlay.swift` shows a floating indicator during recording:
- `FloatingPanel` (NSPanel subclass) with `canBecomeKey: false` / `canBecomeMain: false` to **never steal focus**
- Audio wave bars animate based on RMS audio level
- Stop button to end recording
- Saves and reactivates the previous frontmost app after showing

### Model Loading

WhisperKit handles download + CoreML compilation in a single init:
- First run: 1-5+ minutes (CoreML compiles for the chip)
- Subsequent runs: 10-30 seconds (cached)
- Model loads automatically on app launch (`AppState.init()`)

### Available Models

| ID | Name | Size |
|----|------|------|
| `openai_whisper-base` | Base | ~80 MB |
| `openai_whisper-small` | Small | ~216 MB |
| `openai_whisper-large-v3-v20240930_turbo` | Large V3 Turbo | ~632 MB |
| `openai_whisper-large-v3-v20240930` | Large V3 | ~1.5 GB |

### Supported Languages

Spanish (default), English, Portuguese, French, German, Italian, Japanese, Korean, Chinese.

## Entitlements

| Key | Purpose |
|-----|---------|
| `com.apple.security.device.audio-input` | Microphone access |
| `com.apple.security.automation.apple-events` | Send events to other apps (paste) |

**Warning**: XcodeGen can empty `Wisper.entitlements` on regeneration. The `properties` block in `project.yml` under `entitlements` ensures they're restored. Always verify after `xcodegen generate`.

## Info.plist Keys

| Key | Value | Purpose |
|-----|-------|---------|
| `LSUIElement` | `true` | Menu bar only, no Dock icon |
| `NSMicrophoneUsageDescription` | Usage string | Microphone permission dialog |
| `NSAppleEventsUsageDescription` | Usage string | Automation permission dialog |

## Recording Modes

- **Push to Talk**: Hold hotkey to record, release to stop
- **Toggle**: Press hotkey once to start, press again to stop

## Transcription Modes

- **Streaming**: Text injected in real-time as chunks are transcribed (3s intervals)
- **On Release**: All text injected at once when recording stops

## Concurrency Model

- `AppState` is `@MainActor` — all UI state on main thread
- `TranscriptionEngine`, `TextInjector`, `HotkeyManager` are `@unchecked Sendable`
- Audio processing on background `DispatchQueue` with `NSLock` for accumulator
- Text injection on dedicated `pasteQueue` (`.userInteractive` QoS)
- Callbacks from engines to AppState go through `Task { @MainActor in ... }`

## GitHub

Repository: [github.com/andresilvagomez/wisper](https://github.com/andresilvagomez/wisper)
