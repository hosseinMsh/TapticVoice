import Foundation

/// Preconfigured acoustic mastering presets tuned for the Force Touch trackpad glass.
public enum AcousticPreset: String, CaseIterable, Identifiable, Codable {
    case clear
    case loud
    case tactile
    case custom

    public var id: String { rawValue }
}

/// Complete acoustic and haptic signal-processing configuration.
public struct HapticAudioConfig: Equatable {
    public var preset: AcousticPreset
    public var highPassHz: Double
    public var lowPassHz: Double
    public var eq1kGainDB: Double
    public var eq2kGainDB: Double
    public var compressionAmount: Double // 0.0 ... 1.0
    public var formantClarity: Double    // 0.0 ... 1.0 (maps F2 emphasis)
    public var pitchShiftSemitones: Double // -6.0 ... +6.0
    public var speechSpeed: Double       // 0.7 ... 1.4
    public var motorIntensity: Double    // 0.3 ... 1.0

    public init(
        preset: AcousticPreset = .clear,
        highPassHz: Double = 120.0,
        lowPassHz: Double = 3800.0,
        eq1kGainDB: Double = 3.5,
        eq2kGainDB: Double = 4.5,
        compressionAmount: Double = 0.55,
        formantClarity: Double = 0.65,
        pitchShiftSemitones: Double = 0.0,
        speechSpeed: Double = 1.0,
        motorIntensity: Double = 1.0
    ) {
        self.preset = preset
        self.highPassHz = highPassHz
        self.lowPassHz = lowPassHz
        self.eq1kGainDB = eq1kGainDB
        self.eq2kGainDB = eq2kGainDB
        self.compressionAmount = compressionAmount
        self.formantClarity = formantClarity
        self.pitchShiftSemitones = pitchShiftSemitones
        self.speechSpeed = speechSpeed
        self.motorIntensity = motorIntensity
    }

    /// Returns default tuned parameters for a given acoustic preset while preserving user speed/pitch.
    public mutating func applyPreset(_ newPreset: AcousticPreset) {
        self.preset = newPreset
        switch newPreset {
        case .clear:
            highPassHz = 120.0
            lowPassHz = 3800.0
            eq1kGainDB = 3.5
            eq2kGainDB = 4.5
            compressionAmount = 0.55
            formantClarity = 0.65
            motorIntensity = 1.0
        case .loud:
            highPassHz = 140.0
            lowPassHz = 3850.0
            eq1kGainDB = 5.0
            eq2kGainDB = 6.0
            compressionAmount = 0.90
            formantClarity = 0.80
            motorIntensity = 1.0
        case .tactile:
            highPassHz = 95.0
            lowPassHz = 3400.0
            eq1kGainDB = 2.0
            eq2kGainDB = 2.5
            compressionAmount = 0.40
            formantClarity = 0.35
            motorIntensity = 1.0
        case .custom:
            break
        }
    }
}

/// Digital Signal Processing pipeline optimizing 16 kHz audio for trackpad acoustic projection.
public enum HapticDSP {
    /// Standard direct-form I Biquad IIR filter.
    public struct Biquad {
        public var b0: Double = 1, b1: Double = 0, b2: Double = 0
        public var a1: Double = 0, a2: Double = 0
        private var x1: Double = 0, x2: Double = 0
        private var y1: Double = 0, y2: Double = 0

        public init(b0: Double = 1, b1: Double = 0, b2: Double = 0, a1: Double = 0, a2: Double = 0) {
            self.b0 = b0
            self.b1 = b1
            self.b2 = b2
            self.a1 = a1
            self.a2 = a2
        }

        public mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
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

    public static func makePeakingEQ(freq: Double, q: Double = 1.2, gainDB: Double, sampleRate: Double = 16000) -> Biquad {
        let amp = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * freq / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosw = cos(w0)
        let a0 = 1.0 + alpha / amp
        return Biquad(
            b0: (1.0 + alpha * amp) / a0,
            b1: -2.0 * cosw / a0,
            b2: (1.0 - alpha * amp) / a0,
            a1: -2.0 * cosw / a0,
            a2: (1.0 - alpha / amp) / a0
        )
    }

    /// Processes a 16 kHz mono buffer in-place using Biquad EQ, dynamic leveling, and soft limiting.
    public static func master(samples: inout [Float], config: HapticAudioConfig, sampleRate: Double = 16000) {
        guard !samples.isEmpty else { return }

        var hp = makeHighPass(freq: max(60, min(300, config.highPassHz)), q: 0.707, sampleRate: sampleRate)
        var lp = makeLowPass(freq: max(2000, min(4200, config.lowPassHz)), q: 0.707, sampleRate: sampleRate)
        var eq1k = makePeakingEQ(freq: 1000, q: 1.2, gainDB: config.eq1kGainDB, sampleRate: sampleRate)
        var eq2k = makePeakingEQ(freq: 2200, q: 1.2, gainDB: config.eq2kGainDB, sampleRate: sampleRate)

        for i in samples.indices {
            var s = Double(samples[i])
            s = hp.process(s)
            s = lp.process(s)
            s = eq1k.process(s)
            s = eq2k.process(s)
            samples[i] = Float(s)
        }

        // Dynamic compression + makeup gain scaled by compressionAmount
        let comp = max(0.0, min(1.0, Float(config.compressionAmount)))
        if comp > 0.01 {
            var envelope: Float = 0.0
            let attack: Float = 0.06
            let release: Float = 0.002
            let threshold: Float = 0.28 - 0.12 * comp
            let ratioPower: Float = 0.20 + 0.35 * comp
            let makeup: Float = 1.0 + 0.55 * comp

            for i in samples.indices {
                let mag = abs(samples[i])
                if mag > envelope {
                    envelope += attack * (mag - envelope)
                } else {
                    envelope += release * (mag - envelope)
                }
                let dynGain: Float = envelope > threshold
                    ? pow(threshold / max(envelope, 1e-4), ratioPower)
                    : makeup
                samples[i] *= dynGain
            }
        }

        // Normalize gently and apply tanh soft saturation limiter to prevent harsh motor clipping
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let normScale: Float = peak > 0.01 ? min(1.8, 0.92 / peak) : 1.0
        for i in samples.indices {
            let driven = samples[i] * normScale
            samples[i] = Float(tanh(Double(driven)))
        }
    }
}
