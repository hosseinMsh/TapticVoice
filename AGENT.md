# AGENT.md — AI Developer & Maintainer Guide

This file provides essential architectural context, invariants, and workflows for AI coding agents and contributors working on **TapticVoice Studio**.

---

## 1. Mission & Target Platform

- **Product:** Native macOS desktop application (**`TapticVoice.app`**) that turns a MacBook's Force Touch trackpad (or Magic Trackpad 2+) into a physical acoustic speaker using haptic resonance (`100 Hz – 4000 Hz`).
- **Platform Scope:** **macOS 13.0+ (Apple Silicon `arm64` & Intel `x86_64`) only.** Do not add iOS, Linux, Windows, Python server, or web UI code.
- **Offline-First Principle:** English (`en_US`) and Persian (`fa_IR`) speech synthesis MUST work **100% offline out-of-the-box** with zero external runtime dependencies (no system Python, no Homebrew, no FFmpeg, no `pip`).

---

## 2. Repository Structure

```text
TapticVoice/
├── .github/workflows/ci-cd.yml       # Automated test, dylib bundling, codesign & release workflow
├── AGENT.md                          # This guide (architecture & developer invariants)
├── RULES.md                          # Strict coding, UI, DSP, and Git hygiene rules
├── CHANGELOG.md                      # Version history (Keep a Changelog)
├── README.md                         # Public project documentation (EN + FA)
├── LICENSE                           # MIT License
├── package_release.sh                # Packages TapticVoice.app into dist/TapticVoice-v<ver>-macOS.zip
├── assets/
│   └── icon.png                      # README & branding preview icon (1024px)
└── apps/TapticVoice/
    ├── Package.swift                 # Swift Package manifest (TapticVoice + TapticVoiceTests)
    ├── build_app.sh                  # Compiles Swift package, embeds dylibs/models, signs .app
    ├── generate_icon.py              # Regenerates AppIcon.icns cleanly (build-time utility)
    ├── scripts/
    │   ├── fetch_deps.sh             # Downloads Sherpa-ONNX universal2 libs & tiny EN/FA models
    │   └── run_tests.sh              # Runs XCTest suite or TapticCoreVerify on CLT-only Macs
    ├── Assets/
    │   └── AppIcon.icns              # Compiled macOS multi-resolution Retina icon
    ├── Vendor/                       # [GITIGNORED] Downloaded dylibs and bundled EN/FA models
    ├── Sources/
    │   ├── CSherpaOnnx/              # C modulemap + v1.13.8 header bridging libsherpa-onnx-c-api
    │   ├── TapticCore/               # Pure Swift testable library module
    │   │   ├── Core/
    │   │   │   ├── Audio/            # HapticDSP (Biquad filters, presets, limiter), AudioResampler
    │   │   │   ├── Haptics/          # MultitouchBridge, LPCAnalyzer, HapticEngine
    │   │   │   └── TTS/              # SherpaOnnxBridge, TextScriptSegmenter, LanguagePackManager, SystemTTSFallback
    │   │   └── Localization/         # Type-safe bilingual L10n (EN LTR / FA RTL)
    │   └── TapticVoice/              # SwiftUI executable target
    │       ├── App/                  # @main TapticVoiceApp & AppState coordinator
    │       ├── Resources/            # Info.plist
    │       └── UI/                   # MainView, ControlsPanel, WaveformVisualizer, LanguagePacksSheet
    └── Tests/
        ├── TapticCoreVerify/         # Standalone test runner (works with CLT-only Macs)
        └── TapticVoiceTests/         # XCTest suite (runs on full Xcode / CI)
```

---

## 3. Core Technical Invariants

1. **Private Hardware Framework (`MultitouchSupport`):**
   - `MultitouchBridge.swift` dynamically loads `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport` via `dlopen`/`dlsym`.
   - **Sandbox Caveat:** Running inside restricted agent/terminal sandboxes cannot enumerate IOKit trackpad devices (`MTDeviceCreateList` returns empty). Hardware playback must be tested from a regular macOS GUI launch (`open apps/TapticVoice/build/TapticVoice.app`) or an unsandboxed terminal.
   - **Safety Cap:** Actuation level passed to `MTActuationActuate` MUST remain clamped in `0.0 ... 1.0`.

2. **16 kHz Float32 Mono Audio Contract:**
   - `LPCAnalyzer` assumes `sampleRate = 16000.0`, `hop = 0.010` (10 ms), `win = 0.025` (25 ms, 400 samples), `order = 18`.
   - Every TTS output (whether `22050 Hz` from Piper ONNX or `24000 Hz` from `AVSpeechSynthesizer`) MUST be converted via `AudioResampler` to `16000 Hz Float32 mono` before entering `HapticDSP` and `LPCAnalyzer`.
   - Keep audio passing **in memory (`[Float]`)** directly from TTS -> `HapticDSP` -> `HapticEngine`; only write temporary `.wav` files when the user clicks Speaker Preview (`AVAudioPlayer`).

3. **Real-Time Audio Thread Hygiene:**
   - Never invoke `DispatchQueue.main.async` on every 4–8 ms pitch cycle inside `HapticEngine`.
   - Update an `NSLock`/`os_unfair_lock`-protected `TelemetrySnapshot` in the audio thread and let `WaveformVisualizer` poll at ~30–60 Hz on the main thread.

4. **Portable `.dylib` Linking (`@rpath` / `@executable_path/../Frameworks`):**
   - All embedded `.dylib` files (`libsherpa-onnx-c-api.dylib`, `libonnxruntime*.dylib`) live inside `TapticVoice.app/Contents/Frameworks/`.
   - Always verify zero references to `/opt/homebrew`, `/usr/local`, or `/Library/Frameworks/Python` via `otool -L`.

5. **Swift Compilation in Restricted Environments:**
   - If `xcode-select` points to Command Line Tools inside a sandboxed shell, pass `-module-cache-path /tmp/clang-cache` (or `DEVELOPER_DIR=/Library/Developer/CommandLineTools`) as needed.

---

## 4. Standard Commands

```bash
# 1. Fetch & quantize offline Sherpa-ONNX libs + tiny EN/FA models (once / cached)
./apps/TapticVoice/scripts/fetch_deps.sh

# 2. Run unit tests & offline synthesis verification
./apps/TapticVoice/scripts/run_tests.sh

# 3. Build self-contained TapticVoice.app
./apps/TapticVoice/build_app.sh

# 4. Verify portability & signature
plutil -lint apps/TapticVoice/build/TapticVoice.app/Contents/Info.plist
codesign -vvv --deep apps/TapticVoice/build/TapticVoice.app
otool -L apps/TapticVoice/build/TapticVoice.app/Contents/MacOS/TapticVoice

# 5. Package distributable release archive
./package_release.sh
```
