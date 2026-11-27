# RULES.md — Engineering, Code Quality & Release Standards

All contributions (human or AI agent) to **TapticVoice Studio** must adhere to the following rules.

---

## 1. Platform & Dependency Discipline

1. **macOS Exclusive:** Code targets **macOS 13.0+** (`arm64` & `x86_64`) using Swift, SwiftUI, AppKit, AVFoundation, and IOKit/MultitouchSupport. Do not add cross-platform shims, web servers, or Electron/Python wrappers.
2. **Zero External Runtime Dependencies:** The released `TapticVoice.app` MUST run on a fresh MacBook without requiring Python, Homebrew, FFmpeg, eSpeak CLI, or internet access for core English & Persian synthesis.
3. **No Large Binary Blobs in Git:** Never commit `.onnx`, `.dylib`, `.a`, `.tar.bz2`, `.zip`, `.wav`, `.mp3`, `.app`, or `Vendor/` artifacts into Git. Fetch and cache them in `apps/TapticVoice/scripts/fetch_deps.sh` and CI/CD.

---

## 2. Bilingual Code & UI Rules

1. **Code in Clean English:** All Swift file names, types, functions, properties, comments, and `///` docstrings MUST be written in clear, idiomatic English.
2. **No Hardcoded UI Strings:** Every visible label, tooltip, error message, preset name, and accessibility label in SwiftUI views MUST come from `L10n`.
3. **First-Class EN & FA Support:**
   - UI MUST support live switching between **English** (`layoutDirection = .leftToRight`) and **Persian** (`layoutDirection = .rightToLeft`) without restarting the app.
   - Any newly added `L10n` key must be added to **both** `.english` and `.persian` dictionaries (enforced by `L10nTests`).
4. **Clean, Minimalist UX:** Avoid redundant controls, placeholder badges, or debug noise in production views. Keep controls grouped logically (`Presets`, `Tone & Clarity`, `Hardware`).

---

## 3. Audio, DSP & Haptics Safety

1. **Normalized Audio Pipeline:** Maintain `16,000 Hz Float32` mono format across `AudioResampler`, `HapticDSP`, and `LPCAnalyzer`.
2. **Hardware Safety:**
   - Always clamp actuator strength in `[0.0, 1.0]` before passing to `MTActuationActuate`.
   - High-pass filter below `90–120 Hz` (depending on preset) to avoid saturating the Force Touch motor coil with sub-audible DC/rumble.
   - Apply smooth soft limiting (`tanh`) after EQ boosts to prevent harsh clipping.
3. **Thread Safety:**
   - Protect `TelemetrySnapshot` with a lock; never allocate SwiftUI updates on every haptic cycle.
   - Always support immediate cancellation (`stop()`) and release `MTActuation` CF/unmanaged references without leaks.

---

## 4. Testing & Verification Requirements

Before marking any feature or refactor complete:
1. Run `swift test` in `apps/TapticVoice/` and ensure 100% pass rate with zero skipped assertions.
2. Run `./apps/TapticVoice/build_app.sh` and verify:
   - `plutil -lint` succeeds on `Info.plist`.
   - `codesign -vvv --deep` reports a valid signature.
   - `otool -L` on the binary and embedded `.dylib`s shows **zero** `/opt/homebrew` or machine-specific absolute paths.
3. Update `CHANGELOG.md` under `[Unreleased]` or the target release version before tagging.

---

## 5. Git & Release Workflow

- **Commit Style:** Use Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `ci:`, `chore:`).
- **Versioning:** Follow Semantic Versioning (`vMAJOR.MINOR.PATCH`).
- **Releases:** Always publish releases by pushing a signed/annotated git tag (`vX.Y.Z`) so GitHub Actions builds, tests, bundles, and publishes artifacts deterministically.
