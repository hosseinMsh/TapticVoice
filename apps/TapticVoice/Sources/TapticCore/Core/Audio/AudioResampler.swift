import Foundation
import AVFoundation

/// Resamples arbitrary PCM/compressed audio into 16 kHz Float32 mono buffers and writes preview WAVs.
public enum AudioResampler {
    public static let targetSampleRate: Double = 16000.0

    /// Resamples raw Float32 mono samples from `sourceRate` to `16000 Hz`.
    public static func resampleTo16k(samples: [Float], sourceRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if abs(sourceRate - targetSampleRate) < 1.0 {
            return samples
        }

        guard let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false),
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            return linearResample(samples: samples, from: sourceRate, to: targetSampleRate)
        }

        srcBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let ch = srcBuffer.floatChannelData?[0] {
            _ = samples.withUnsafeBufferPointer { ptr in
                memcpy(ch, ptr.baseAddress!, samples.count * MemoryLayout<Float>.size)
            }
        }

        let dstCapacity = AVAudioFrameCount(Double(samples.count) * targetSampleRate / sourceRate) + 1024
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstCapacity) else {
            return linearResample(samples: samples, from: sourceRate, to: targetSampleRate)
        }

        var fed = false
        var error: NSError?
        converter.convert(to: dstBuffer, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return srcBuffer
        }

        guard error == nil, let outCh = dstBuffer.floatChannelData?[0] else {
            return linearResample(samples: samples, from: sourceRate, to: targetSampleRate)
        }
        return Array(UnsafeBufferPointer(start: outCh, count: Int(dstBuffer.frameLength)))
    }

    /// Reads an audio file (WAV, AIFF, MP3, CAF) and converts it into a 16 kHz Float32 mono array.
    public static func decodeFileTo16k(url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try file.read(into: srcBuffer)
        } catch {
            return nil
        }

        guard let srcCh = srcBuffer.floatChannelData?[0] else { return nil }
        let raw = Array(UnsafeBufferPointer(start: srcCh, count: Int(srcBuffer.frameLength)))
        return resampleTo16k(samples: raw, sourceRate: srcFormat.sampleRate)
    }

    /// Concatenates audio segments with a smooth cosine crossfade to prevent clicks between languages.
    public static func concatenateWithCrossfade(_ segments: [[Float]], fadeSamples: Int = 480) -> [Float] {
        let nonEmpty = segments.filter { !$0.isEmpty }
        guard let first = nonEmpty.first else { return [] }
        if nonEmpty.count == 1 { return first }

        var output = first
        for seg in nonEmpty.dropFirst() {
            let fade = min(fadeSamples, min(output.count, seg.count) / 2)
            if fade > 8 {
                let startIdx = output.count - fade
                for i in 0..<fade {
                    let t = Float(i) / Float(fade)
                    let outGain = cos(t * .pi * 0.5)
                    let inGain = sin(t * .pi * 0.5)
                    output[startIdx + i] = output[startIdx + i] * outGain + seg[i] * inGain
                }
                output.append(contentsOf: seg.dropFirst(fade))
            } else {
                output.append(contentsOf: seg)
            }
        }
        return output
    }

    /// Writes Float32 16 kHz mono samples into a WAV file for `AVAudioPlayer` speaker preview.
    public static func writeWav16k(samples: [Float], to url: URL) -> Bool {
        guard !samples.isEmpty else { return false }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false) else {
            return false
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return false
        }

        buf.frameLength = AVAudioFrameCount(samples.count)
        guard let ch = buf.floatChannelData?[0] else { return false }
        _ = samples.withUnsafeBufferPointer { ptr in
            memcpy(ch, ptr.baseAddress!, samples.count * MemoryLayout<Float>.size)
        }

        do {
            try file.write(from: buf)
            return true
        } catch {
            return false
        }
    }

    private static func linearResample(samples: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
        let ratio = dstRate / srcRate
        let outCount = max(1, Int(Double(samples.count) * ratio))
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let pos = Double(i) / ratio
            let idx = Int(pos)
            let frac = Float(pos - Double(idx))
            let s0 = samples[min(idx, samples.count - 1)]
            let s1 = samples[min(idx + 1, samples.count - 1)]
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }
}
