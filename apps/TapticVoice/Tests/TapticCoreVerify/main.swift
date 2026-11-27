import Foundation
import TapticCore

/// Standalone test runner usable even on CommandLineTools-only Macs without Xcode XCTest.
@main
struct TapticCoreVerify {
    static func assertTrue(_ cond: Bool, _ msg: String) {
        if !cond {
            fputs("FAILED: \(msg)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        print("[1/5] Testing LPCAnalyzer...")
        let sr = 16000.0
        let n = Int(sr * 0.25)
        let tone: [Float] = (0..<n).map { i in
            let t = Double(i) / sr
            let env = 0.5 + 0.5 * sin(2.0 * .pi * 150.0 * t)
            return Float(env * (0.7 * sin(2.0 * .pi * 600.0 * t) + 0.4 * sin(2.0 * .pi * 1600.0 * t)))
        }
        let frames = LPCAnalyzer.analyze(tone, trimSilence: true)
        let voiced = frames.filter { $0.voiced }
        assertTrue(!voiced.isEmpty, "No voiced frames found")
        let avgF1 = voiced.map { $0.formants[0] }.reduce(0, +) / Double(voiced.count)
        let avgF2 = voiced.map { $0.formants[1] }.reduce(0, +) / Double(voiced.count)
        assertTrue((450...750).contains(avgF1), "F1 out of range: \(avgF1)")
        assertTrue((1350...1850).contains(avgF2), "F2 out of range: \(avgF2)")
        print("      OK (avgF1=\(Int(avgF1)) Hz, avgF2=\(Int(avgF2)) Hz)")

        print("[2/5] Testing HapticDSP...")
        var rumble: [Float] = (0..<4000).map { i in
            Float(0.9 * sin(2.0 * .pi * 40.0 * Double(i) / sr))
        }
        HapticDSP.master(samples: &rumble, config: HapticAudioConfig(preset: .clear), sampleRate: sr)
        let maxRumble = rumble.dropFirst(400).reduce(Float(0)) { max($0, abs($1)) }
        assertTrue(maxRumble < 0.45, "Sub-120Hz rumble not attenuated: \(maxRumble)")
        assertTrue(rumble.allSatisfy { $0 >= -1.0 && $0 <= 1.0 }, "Samples exceeded [-1, 1]")
        print("      OK (40Hz attenuated to \(String(format: "%.3f", maxRumble)))")

        print("[3/5] Testing TextScriptSegmenter...")
        let segs = TextScriptSegmenter.segment("سلام! اپلیکیشن TapticVoice عالی است.", installedLanguageIds: ["fa_IR", "en_US"])
        assertTrue(segs.count == 3, "Expected 3 segments, got \(segs.count)")
        assertTrue(segs[0].languageId == "fa_IR" && segs[1].languageId == "en_US" && segs[2].languageId == "fa_IR", "Wrong segment languages")
        let frSegs = TextScriptSegmenter.segment("Bonjour tout le monde", installedLanguageIds: ["fa_IR", "en_US", "fr_FR"])
        assertTrue(frSegs.count == 1 && frSegs[0].languageId == "fr_FR", "French auto-detection failed")
        print("      OK (Mixed FA/EN + downloaded French detection verified)")

        print("[4/5] Testing L10n completeness...")
        for key in L10nKey.allCases {
            assertTrue(!(L10n.en[key]?.isEmpty ?? true), "Missing EN key: \(key)")
            assertTrue(!(L10n.fa[key]?.isEmpty ?? true), "Missing FA key: \(key)")
        }
        print("      OK (\(L10nKey.allCases.count) bilingual keys verified)")

        print("[5/5] Testing live offline Sherpa-ONNX Persian & English synthesis...")
        let manager = LanguagePackManager()
        assertTrue(manager.bridge.isRuntimeAvailable, "SherpaOnnxBridge runtime failed to dlopen")
        assertTrue(manager.resolveModelFiles(for: "fa_IR") != nil, "fa_IR bundled model missing")
        assertTrue(manager.resolveModelFiles(for: "en_US") != nil, "en_US bundled model missing")

        let faSamples = manager.synthesizeOffline(text: "سلام، من صدای آفلاین فارسی هستم.", forcedLanguageId: "fa_IR", speed: 1.0)
        assertTrue((faSamples?.count ?? 0) > 8000, "Persian synthesis too short or nil: \(faSamples?.count ?? 0)")

        let enSamples = manager.synthesizeOffline(text: "Hello from offline trackpad synthesis.", forcedLanguageId: "en_US", speed: 1.0)
        assertTrue((enSamples?.count ?? 0) > 8000, "English synthesis too short or nil: \(enSamples?.count ?? 0)")

        var mixedSamples = manager.synthesizeOffline(text: "سلام TapticVoice", forcedLanguageId: nil, speed: 1.0)!
        assertTrue(mixedSamples.count > 8000, "Mixed synthesis failed")
        HapticDSP.master(samples: &mixedSamples, config: HapticAudioConfig(preset: .loud))
        let analyzedFrames = LPCAnalyzer.analyze(mixedSamples)
        assertTrue(!analyzedFrames.isEmpty, "LPC analysis on mastered offline speech produced 0 frames")

        print("      OK (fa=\(faSamples!.count) samples, en=\(enSamples!.count) samples, mixed=\(mixedSamples.count) samples -> \(analyzedFrames.count) haptic frames)")
        print("ALL VERIFICATION CHECKS PASSED!")
    }
}
