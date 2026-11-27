import Foundation
import AVFoundation

/// Zero-dependency offline fallback using macOS native `AVSpeechSynthesizer` audio buffer capture.
public final class SystemTTSFallback: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// Synthesizes `text` into 16 kHz Float32 mono samples using a macOS system voice.
    public func synthesize(text: String, languageCode: String = "en-US", speed: Double = 1.0) -> [Float]? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: "en-US")
        let normalizedRate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(max(0.7, min(1.4, speed)))
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, normalizedRate))

        let semaphore = DispatchSemaphore(value: 0)
        var collected: [Float] = []
        var detectedRate: Double = 22050.0
        var hasFinished = false

        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                if !hasFinished {
                    hasFinished = true
                    semaphore.signal()
                }
                return
            }

            if pcm.frameLength == 0 {
                if !hasFinished {
                    hasFinished = true
                    semaphore.signal()
                }
                return
            }

            detectedRate = pcm.format.sampleRate
            if let floatData = pcm.floatChannelData?[0] {
                collected.append(contentsOf: UnsafeBufferPointer(start: floatData, count: Int(pcm.frameLength)))
            } else if let int16Data = pcm.int16ChannelData?[0] {
                let count = Int(pcm.frameLength)
                for i in 0..<count {
                    collected.append(Float(int16Data[i]) / 32768.0)
                }
            }
        }

        _ = semaphore.wait(timeout: .now() + 15.0)
        guard !collected.isEmpty else { return nil }
        return AudioResampler.resampleTo16k(samples: collected, sourceRate: detectedRate)
    }
}
