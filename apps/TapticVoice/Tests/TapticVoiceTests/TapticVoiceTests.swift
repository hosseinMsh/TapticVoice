import XCTest
@testable import TapticCore

final class TapticVoiceTests: XCTestCase {
    func testLPCAnalyzerExtractsPitchAndFormants() {
        let sampleRate = 16000.0
        let count = Int(sampleRate * 0.25)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let env = 0.5 + 0.5 * sin(2.0 * .pi * 150.0 * t)
            let sig = env * (0.7 * sin(2.0 * .pi * 600.0 * t) + 0.4 * sin(2.0 * .pi * 1600.0 * t))
            samples[i] = Float(sig)
        }

        let frames = LPCAnalyzer.analyze(samples, trimSilence: true)
        XCTAssertFalse(frames.isEmpty)
        let voicedFrames = frames.filter { $0.voiced }
        XCTAssertFalse(voicedFrames.isEmpty)

        let avgF1 = voicedFrames.map { $0.formants[0] }.reduce(0, +) / Double(voicedFrames.count)
        let avgF2 = voicedFrames.map { $0.formants[1] }.reduce(0, +) / Double(voicedFrames.count)
        XCTAssertTrue((450...750).contains(avgF1), "Expected F1 near 600 Hz, got \(avgF1)")
        XCTAssertTrue((1350...1850).contains(avgF2), "Expected F2 near 1600 Hz, got \(avgF2)")
    }

    func testHapticDSPClampsAndAttenuatesSubBass() {
        let sampleRate = 16000.0
        let count = 4000
        var rumble = (0..<count).map { i in
            Float(0.9 * sin(2.0 * .pi * 40.0 * Double(i) / sampleRate))
        }
        let cfg = HapticAudioConfig(preset: .clear)
        HapticDSP.master(samples: &rumble, config: cfg, sampleRate: sampleRate)

        let maxMag = rumble.dropFirst(400).reduce(Float(0)) { max($0, abs($1)) }
        XCTAssertLessThan(maxMag, 0.45, "Sub-120 Hz rumble should be attenuated")
        XCTAssertTrue(rumble.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }

    func testTextScriptSegmenterSplitsPersianAndEnglish() {
        let mixed = "سلام! اپلیکیشن TapticVoice عالی است."
        let segments = TextScriptSegmenter.segment(mixed, forcedLanguageId: nil, installedLanguageIds: ["fa_IR", "en_US"])

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].languageId, "fa_IR")
        XCTAssertEqual(segments[1].languageId, "en_US")
        XCTAssertEqual(segments[1].text, "TapticVoice")
        XCTAssertEqual(segments[2].languageId, "fa_IR")
    }

    func testTextScriptSegmenterRoutesDownloadedLatinLanguages() {
        let french = "Bonjour tout le monde"
        let segments = TextScriptSegmenter.segment(french, forcedLanguageId: nil, installedLanguageIds: ["fa_IR", "en_US", "fr_FR"])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].languageId, "fr_FR")
    }

    func testLocalizationCompletenessForENAndFA() {
        for key in L10nKey.allCases {
            XCTAssertNotNil(L10n.en[key], "Missing EN localization for \(key)")
            XCTAssertNotNil(L10n.fa[key], "Missing FA localization for \(key)")
            XCTAssertFalse(L10n.en[key]?.isEmpty ?? true)
            XCTAssertFalse(L10n.fa[key]?.isEmpty ?? true)
        }
    }

    func testOfflineSherpaSynthesisWhenBundledOrCached() throws {
        let manager = LanguagePackManager()
        guard manager.bridge.isRuntimeAvailable,
              manager.resolveModelFiles(for: "fa_IR") != nil,
              manager.resolveModelFiles(for: "en_US") != nil else {
            throw XCTSkip("Vendor offline models/dylib not downloaded yet; skipping live synthesis integration check.")
        }

        let faSamples = manager.synthesizeOffline(text: "سلام دنیا", forcedLanguageId: "fa_IR", speed: 1.0)
        XCTAssertNotNil(faSamples)
        XCTAssertGreaterThan(faSamples?.count ?? 0, 1600)

        let mixedSamples = manager.synthesizeOffline(text: "سلام TapticVoice", forcedLanguageId: nil, speed: 1.0)
        XCTAssertNotNil(mixedSamples)
        XCTAssertGreaterThan(mixedSamples?.count ?? 0, 3200)
    }
}
