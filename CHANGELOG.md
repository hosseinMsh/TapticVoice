# Changelog

All notable changes to **TapticVoice Studio** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] - 2026-11-28

### Added
- **100% Offline Multi-Language TTS Engine (`SherpaOnnxBridge`):**
  - Integrated native C-API `sherpa-onnx` (`libsherpa-onnx-c-api.dylib` + `libonnxruntime.dylib`) directly in Swift — zero Python, PyInstaller, or FFmpeg required.
  - Bundled tiny `int8`-quantized offline **Persian (`fa_IR`)** and **English (`en_US`)** neural voices inside `TapticVoice.app` out-of-the-box, with automatic macOS `AVSpeechSynthesizer` fallback.
- **Downloadable Offline Language Packs (`LanguagePackManager` & `LanguagePacksSheet`):**
  - Browse, download, extract, activate, and remove additional offline Piper VITS voice packs (Arabic, Turkish, French, German, Spanish, Russian, Italian, Chinese) inside `~/Library/Application Support/TapticVoice/Models/`.
- **Mixed-Language Auto Segmentation (`TextScriptSegmenter`):**
  - Automatically splits mixed Persian/English/multi-script text using Unicode script analysis + Apple `NaturalLanguage`, synthesizing each segment in its native voice with smooth crossfading.
- **Pro Acoustic & Haptic Quality Controls (`ControlsPanel` & `HapticDSP`):**
  - Added acoustic presets (`Clear Voice`, `Loud / Desk`, `Tactile Feel`, `Custom`).
  - Added Formant Clarity ($F_2$ Emphasis) slider, Pitch Shift (semitones), Compression Boost, Speed (`0.7x–1.4x`), and External Magic Trackpad toggle.
  - Added `tanh` soft-saturation limiter to maximize perceived dB without motor stalling.
- **Bilingual Codebase & Live EN/FA UI (`L10n`):**
  - Complete bilingual UI switcher (English LTR ↔ فارسی RTL) with localized presets, telemetry, and error banners.
- **Engineering Governance & Test Suite:**
  - Added `AGENT.md`, `RULES.md`, `CHANGELOG.md`, `Package.swift`, and unit tests (`LPCAnalyzerTests`, `HapticDSPTests`, `TextScriptSegmenterTests`, `L10nTests`).
- **Upgraded CI/CD Pipeline:**
  - Added automated `swift test` stage, `Vendor/` dependency caching, `otool -L` portability verification, and `CHANGELOG`-aware release publishing.

### Changed
- Refactored monolithic Swift files into clean modules (`App`, `Core/Audio`, `Core/Haptics`, `Core/TTS`, `Localization`, `UI`).
- Replaced per-frame `DispatchQueue.main.async` calls in `HapticEngine` with a lock-protected `TelemetrySnapshot` sampled at 30 Hz for jitter-free haptic timing.
- Passed PCM `[Float]` buffers directly in memory instead of writing/re-reading temporary `.wav` files.

### Removed
- Removed legacy Python HTTP web prototype (`server.py`, `web/`).
- Removed Python/PyInstaller/Edge-TTS helper scripts (`taptic_synth.py`, `synth_cli.py`).
- Removed non-MacBook/upstream terminal scripts (`play.sh`, `nospeaker.swift`, `build.sh`) and redundant raw `.iconset` PNGs from Git.

---

## [0.1.1] - 2026-11-25

### Changed
- Replaced external FFmpeg binary dependency with pure Swift Biquad IIR DSP (`HapticDSP`) and native `AVAudioConverter` 16 kHz resampling.
- Packaged standalone PyInstaller synthesizer executable inside `TapticVoice.app/Contents/MacOS/` with macOS `/usr/bin/say` offline fallback.

---

## [0.1.0] - 2026-11-24

### Added
- Initial **TapticVoice Studio** native macOS SwiftUI application (`TapticVoice.app`).
- Custom Apple Squircle Retina icon (`AppIcon.icns`) and 60 FPS formant visualizer.
- Dynamic `MultitouchSupport` haptic motor bridge + 18th-order LPC formant analyzer.
- GitHub Actions macOS build and automated release workflow.
