import Foundation
import AVFoundation
import Combine

public class HapticDSP {
    public struct Biquad {
        var b0: Double = 1, b1: Double = 0, b2: Double = 0
        var a1: Double = 0, a2: Double = 0
        var x1: Double = 0, x2: Double = 0
        var y1: Double = 0, y2: Double = 0

        public mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }

    public static func makeHighPass(freq: Double, q: Double = 0.707, sampleRate: Double = 16000) -> Biquad {
        let w0 = 2.0 * .pi * freq / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw = cos(w0)
        let a0 = 1.0 + alpha
        return Biquad(
            b0: (1.0 + cosw) / (2.0 * a0),
            b1: -(1.0 + cosw) / a0,
            b2: (1.0 + cosw) / (2.0 * a0),
            a1: -2.0 * cosw / a0,
            a2: (1.0 - alpha) / a0
        )
    }

    public static func makeLowPass(freq: Double, q: Double = 0.707, sampleRate: Double = 16000) -> Biquad {
        let w0 = 2.0 * .pi * freq / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw = cos(w0)
        let a0 = 1.0 + alpha
        return Biquad(
            b0: (1.0 - cosw) / (2.0 * a0),
            b1: (1.0 - cosw) / a0,
            b2: (1.0 - cosw) / (2.0 * a0),
            a1: -2.0 * cosw / a0,
            a2: (1.0 - alpha) / a0
        )
    }

    public static func makePeakingEQ(freq: Double, q: Double = 1.2, gainDB: Double = 3.5, sampleRate: Double = 16000) -> Biquad {
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * freq / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw = cos(w0)
        let a0 = 1.0 + alpha / A
        return Biquad(
            b0: (1.0 + alpha * A) / a0,
            b1: -2.0 * cosw / a0,
            b2: (1.0 - alpha * A) / a0,
            a1: -2.0 * cosw / a0,
            a2: (1.0 - alpha / A) / a0
        )
    }

    public static func master(samples: inout [Float], sampleRate: Double = 16000) {
        guard !samples.isEmpty else { return }

        var hp = makeHighPass(freq: 120, q: 0.707, sampleRate: sampleRate)
        var lp = makeLowPass(freq: 3800, q: 0.707, sampleRate: sampleRate)
        var eq1k = makePeakingEQ(freq: 1000, q: 1.2, gainDB: 3.5, sampleRate: sampleRate)
        var eq2k = makePeakingEQ(freq: 2200, q: 1.2, gainDB: 4.0, sampleRate: sampleRate)

        // 1. Filter chain
        for i in 0..<samples.count {
            var s = Double(samples[i])
            s = hp.process(s)
            s = lp.process(s)
            s = eq1k.process(s)
            s = eq2k.process(s)
            samples[i] = Float(s)
        }

        // 2. Dynamic Compressor / Leveler
        var envelope: Float = 0.0
        let attack: Float = 0.05
        let release: Float = 0.002
        for i in 0..<samples.count {
            let inputMag = abs(samples[i])
            if inputMag > envelope {
                envelope += attack * (inputMag - envelope)
            } else {
                envelope += release * (inputMag - envelope)
            }
            let gain: Float = envelope > 0.25 ? pow(0.25 / max(envelope, 0.001), 0.35) : 1.25
            samples[i] = min(1.0, max(-1.0, samples[i] * gain))
        }
    }
}

public class SpeechBridge: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public var isSynthesizing: Bool = false
    @Published public var isSpeakerPlaying: Bool = false
    @Published public var errorMessage: String? = nil

    private var audioPlayer: AVAudioPlayer?
    private var lastGeneratedUrl: URL?

    public override init() {
        super.init()
    }

    public func synthesize(text: String, speedPct: Int, pitchHz: Int, hapticMastering: Bool = true, completion: @escaping (URL?) -> Void) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            completion(nil)
            return
        }

        DispatchQueue.main.async {
            self.isSynthesizing = true
            self.errorMessage = nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let tempDir = FileManager.default.temporaryDirectory
            let rawAudioUrl = tempDir.appendingPathComponent("raw_speech_\(UUID().uuidString).mp3")
            let outWavUrl = tempDir.appendingPathComponent("taptic_speech_\(UUID().uuidString).wav")

            var generatedSuccessfully = false

            // Try bundled standalone binary first
            if let synthBinary = self.findStandaloneSynthBinary() {
                let p = Process()
                p.executableURL = synthBinary
                p.arguments = [rawAudioUrl.path, cleanText, String(speedPct), String(pitchHz)]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    if p.terminationStatus == 0 && FileManager.default.fileExists(atPath: rawAudioUrl.path) {
                        generatedSuccessfully = true
                    }
                } catch {
                    print("Standalone synth failed: \(error)")
                }
            }

            // Fallback to native macOS /usr/bin/say if offline or standalone unavailable
            var sourceUrl = rawAudioUrl
            if !generatedSuccessfully {
                let sayAiff = tempDir.appendingPathComponent("fallback_say_\(UUID().uuidString).aiff")
                let sayProcess = Process()
                sayProcess.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                sayProcess.arguments = ["-o", sayAiff.path, cleanText]
                do {
                    try sayProcess.run()
                    sayProcess.waitUntilExit()
                    if sayProcess.terminationStatus == 0 && FileManager.default.fileExists(atPath: sayAiff.path) {
                        sourceUrl = sayAiff
                        generatedSuccessfully = true
                    }
                } catch {
                    print("Native say fallback failed: \(error)")
                }
            }

            guard generatedSuccessfully, let pcmSamples = self.decodeAndResampleTo16k(sourceUrl: sourceUrl) else {
                DispatchQueue.main.async {
                    self.isSynthesizing = false
                    self.errorMessage = "تولید صوت ناموفق بود. اتصال اینترنت خود را بررسی کنید."
                    completion(nil)
                }
                return
            }

            var processedSamples = pcmSamples
            if hapticMastering {
                HapticDSP.master(samples: &processedSamples, sampleRate: 16000)
            }

            guard self.writePcmToWav(samples: processedSamples, url: outWavUrl) else {
                DispatchQueue.main.async {
                    self.isSynthesizing = false
                    self.errorMessage = "خطا در نوشتن فایل صوتی هپتیک."
                    completion(nil)
                }
                return
            }

            try? FileManager.default.removeItem(at: sourceUrl)

            self.lastGeneratedUrl = outWavUrl
            DispatchQueue.main.async {
                self.isSynthesizing = false
                completion(outWavUrl)
            }
        }
    }

    private func findStandaloneSynthBinary() -> URL? {
        let candidates = [
            Bundle.main.url(forResource: "taptic_synth", withExtension: nil),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/taptic_synth"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/taptic_synth"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/apps/TapticVoice/build/bin/taptic_synth"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/build/bin/taptic_synth")
        ]

        for c in candidates {
            if let c = c, FileManager.default.isExecutableFile(atPath: c.path) {
                return c
            }
        }
        return nil
    }

    private func decodeAndResampleTo16k(sourceUrl: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: sourceUrl) else { return nil }
        let srcFormat = file.processingFormat
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        let srcCapacity = AVAudioFrameCount(file.length)
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: srcCapacity) else { return nil }
        do {
            try file.read(into: srcBuffer)
        } catch {
            return nil
        }

        if srcFormat.sampleRate == 16000 && srcFormat.channelCount == 1 && srcFormat.commonFormat == .pcmFormatFloat32 {
            if let ch = srcBuffer.floatChannelData?[0] {
                return Array(UnsafeBufferPointer(start: ch, count: Int(srcBuffer.frameLength)))
            }
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else { return nil }
        let dstCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * 16000.0 / srcFormat.sampleRate) + 3200
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: dstCapacity) else { return nil }

        var isDone = false
        var error: NSError?
        converter.convert(to: dstBuffer, error: &error) { packetCount, outStatus in
            if isDone {
                outStatus.pointee = .endOfStream
                return nil
            }
            isDone = true
            outStatus.pointee = .haveData
            return srcBuffer
        }

        guard error == nil, let ch = dstBuffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(dstBuffer.frameLength)))
    }

    private func writePcmToWav(samples: [Float], url: URL) -> Bool {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) else {
            return false
        }

        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return false
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        guard let ch = buf.floatChannelData?[0] else { return false }
        for (idx, sample) in samples.enumerated() {
            ch[idx] = sample
        }

        do {
            try file.write(from: buf)
            return true
        } catch {
            return false
        }
    }

    public func playSpeakerPreview(url: URL) {
        stopSpeakerPreview()
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            DispatchQueue.main.async {
                self.isSpeakerPlaying = true
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "خطا در پخش بلندگو: \(error.localizedDescription)"
            }
        }
    }

    public func stopSpeakerPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        DispatchQueue.main.async {
            self.isSpeakerPlaying = false
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeakerPlaying = false
        }
    }
}
