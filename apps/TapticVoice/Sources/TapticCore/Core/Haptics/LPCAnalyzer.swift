import Foundation

/// Represents one 10 ms analyzed vocal-tract frame for haptic playback.
public struct HapticFrame: Equatable {
    public var formants: [Double] = [500, 1500, 2500]
    public var amps: [Double] = [1.0, 0.5, 0.25]
    public var level: Float = 0
    public var voiced: Bool = false
    public var f0: Double = 110.0

    public init(
        formants: [Double] = [500, 1500, 2500],
        amps: [Double] = [1.0, 0.5, 0.25],
        level: Float = 0,
        voiced: Bool = false,
        f0: Double = 110.0
    ) {
        self.formants = formants
        self.amps = amps
        self.level = level
        self.voiced = voiced
        self.f0 = f0
    }
}

/// 18th-order Linear Predictive Coding (LPC) analyzer extracting pitch (F0) and vocal formants (F1, F2, F3).
public enum LPCAnalyzer {
    public static let hopSeconds: Double = 0.010
    public static let sampleRate: Double = 16000.0
    public static let lpcOrder: Int = 18

    private struct Complex {
        var re: Double
        var im: Double

        static func + (l: Complex, r: Complex) -> Complex { Complex(re: l.re + r.re, im: l.im + r.im) }
        static func - (l: Complex, r: Complex) -> Complex { Complex(re: l.re - r.re, im: l.im - r.im) }
        static func * (l: Complex, r: Complex) -> Complex {
            Complex(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re)
        }
        static func / (l: Complex, r: Complex) -> Complex {
            let denom = max(1e-18, r.re * r.re + r.im * r.im)
            return Complex(re: (l.re * r.re + l.im * r.im) / denom, im: (l.im * r.re - l.re * r.im) / denom)
        }
    }

    /// Computes Levinson-Durbin LPC coefficients and prediction error for a windowed signal frame.
    public static func lpcCoefficients(_ x: [Double], order p: Int = lpcOrder) -> ([Double], Double) {
        var r = [Double](repeating: 0, count: p + 1)
        for k in 0...p {
            var sum = 0.0
            for i in k..<x.count {
                sum += x[i] * x[i - k]
            }
            r[k] = sum
        }

        var a = [Double](repeating: 0, count: p + 1)
        a[0] = 1.0
        guard r[0] > 1e-12 else { return (a, 0) }
        r[0] *= 1.0001
        var e = r[0]

        for i in 1...p {
            var acc = r[i]
            for j in 1..<i {
                acc += a[j] * r[i - j]
            }
            let k = -acc / e
            var nextA = a
            for j in 1..<i {
                nextA[j] = a[j] + k * a[i - j]
            }
            nextA[i] = k
            a = nextA
            e *= 1.0 - k * k
        }
        return (a, e)
    }

    /// Finds complex roots of the LPC polynomial using the Durand-Kerner method.
    private static func findRoots(_ a: [Double]) -> [Complex] {
        let p = a.count - 1
        guard p > 0 else { return [] }
        var z = (0..<p).map { k -> Complex in
            let ang = 2.0 * Double.pi * Double(k) / Double(p) + 0.4
            return Complex(re: 0.9 * cos(ang), im: 0.9 * sin(ang))
        }

        func evalPoly(_ x: Complex) -> Complex {
            var s = Complex(re: 1.0, im: 0.0)
            for k in 1...p {
                s = s * x + Complex(re: a[k], im: 0.0)
            }
            return s
        }

        for _ in 0..<300 {
            var moved = 0.0
            for i in 0..<p {
                var denom = Complex(re: 1.0, im: 0.0)
                for j in 0..<p where j != i {
                    denom = denom * (z[i] - z[j])
                }
                if abs(denom.re) < 1e-15 && abs(denom.im) < 1e-15 {
                    denom = Complex(re: 1e-12, im: 0.0)
                }
                let step = evalPoly(z[i]) / denom
                z[i] = z[i] - step
                moved = max(moved, abs(step.re) + abs(step.im))
            }
            if moved < 1e-10 { break }
        }
        return z
    }

    /// Analyzes a 16 kHz mono Float32 buffer into smoothed 10 ms `HapticFrame`s.
    public static func analyze(_ samples: [Float], trimSilence: Bool = true) -> [HapticFrame] {
        let win = Int(0.025 * sampleRate) // 400 samples (25 ms)
        let hopN = Int(hopSeconds * sampleRate) // 160 samples (10 ms)
        guard samples.count >= win else { return [] }

        let hamming = (0..<win).map { 0.54 - 0.46 * cos(2.0 * .pi * Double($0) / Double(win - 1)) }
        var frames: [HapticFrame] = []
        var rmsList: [Double] = []
        var prev = HapticFrame()
        var i = 0

        let minLag = Int(sampleRate / 300.0)
        let maxLag = Int(sampleRate / 70.0)

        while i + win <= samples.count {
            let seg = (0..<win).map { Double(samples[i + $0]) }
            let rms = sqrt(seg.reduce(0.0) { $0 + $1 * $1 } / Double(win))
            rmsList.append(rms)

            var frame = prev
            var zeroCrossings = 0
            for k in 1..<win where (seg[k] >= 0) != (seg[k - 1] >= 0) {
                zeroCrossings += 1
            }

            var bestLag = 0
            var bestCorr = 0.0
            for lag in minLag...maxLag where lag < win - 40 {
                var s = 0.0, ea = 0.0, eb = 0.0
                for k in 0..<(win - lag) {
                    s += seg[k] * seg[k + lag]
                    ea += seg[k] * seg[k]
                    eb += seg[k + lag] * seg[k + lag]
                }
                let r = s / max(sqrt(ea * eb), 1e-12)
                if r > bestCorr {
                    bestCorr = r
                    bestLag = lag
                }
            }

            frame.voiced = bestCorr > 0.35 && (Double(zeroCrossings) / Double(win)) < 0.22
            if frame.voiced && bestLag > 0 {
                frame.f0 = sampleRate / Double(bestLag)
            }

            var preemphasized = [Double](repeating: 0, count: win)
            for k in 0..<win {
                let prevSample = k > 0 ? seg[k - 1] : 0.0
                preemphasized[k] = (seg[k] - 0.97 * prevSample) * hamming[k]
            }

            let (a, err) = lpcCoefficients(preemphasized, order: lpcOrder)
            var candidates: [Double] = []
            if err > 0 {
                for z in findRoots(a) where z.im > 0 {
                    let hz = atan2(z.im, z.re) * sampleRate / (2.0 * .pi)
                    let bw = -log(max(1e-9, sqrt(z.re * z.re + z.im * z.im))) * sampleRate / .pi
                    if hz > 150, hz < 4200, bw < 500 {
                        candidates.append(hz)
                    }
                }
            }

            func pick(_ lo: Double, _ hi: Double, near target: Double) -> Double? {
                candidates.filter { $0 >= lo && $0 <= hi }.min { abs($0 - target) < abs($1 - target) }
            }

            if let f1 = pick(200, 1000, near: prev.formants[0]) { frame.formants[0] = f1 }
            if let f2 = pick(max(frame.formants[0] + 200, 650), 2700, near: prev.formants[1]) { frame.formants[1] = f2 }
            if let f3 = pick(max(frame.formants[1] + 300, 1700), 3900, near: prev.formants[2]) { frame.formants[2] = f3 }

            if err > 0 {
                frame.amps = frame.formants.map { hz in
                    let w = 2.0 * Double.pi * hz / sampleRate
                    var re = 0.0, im = 0.0
                    for k in 0...lpcOrder {
                        re += a[k] * cos(w * Double(k))
                        im -= a[k] * sin(w * Double(k))
                    }
                    return 1.0 / max(sqrt(re * re + im * im), 1e-6)
                }
            }

            frames.append(frame)
            prev = frame
            i += hopN
        }

        let peak = rmsList.max() ?? 1.0
        for idx in frames.indices {
            let rel = rmsList[idx] / max(peak, 1e-9)
            frames[idx].level = rel < 0.02 ? 0 : Float(min(1.0, pow(rel, 0.45)))
            if frames[idx].level == 0 {
                frames[idx].voiced = false
            }
        }

        // 5-frame median smoothing to eliminate isolated tracking glitches
        func median(_ vals: [Double]) -> Double { vals.sorted()[vals.count / 2] }
        let raw = frames
        for idx in frames.indices {
            let lo = max(0, idx - 2)
            let hi = min(frames.count - 1, idx + 2)
            for j in 0..<3 {
                frames[idx].formants[j] = median((lo...hi).map { raw[$0].formants[j] })
            }
            frames[idx].f0 = min(260, max(70, median((lo...hi).map { raw[$0].f0 })))
        }

        if trimSilence {
            while let first = frames.first, first.level == 0 { frames.removeFirst() }
            while let last = frames.last, last.level == 0 { frames.removeLast() }
        }
        return frames
    }

    /// Converts a voiced frame to two weighted formant tones (F1 & F2) modulated by `clarity` (0...1).
    public static func voiceTones(for frame: HapticFrame, clarity: Double = 0.65) -> [(hz: Double, amp: Double)] {
        let f2Boost = 0.8 + 2.2 * max(0.0, min(1.0, clarity))
        let w0 = frame.amps[0]
        let w1 = frame.amps[1] * f2Boost
        let sum = max(w0 + w1, 1e-9)
        return [(frame.formants[0], w0 / sum), (frame.formants[1], w1 / sum)]
    }
}
