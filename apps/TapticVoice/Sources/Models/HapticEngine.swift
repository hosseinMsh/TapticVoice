import Foundation
import AVFoundation
import CoreAudio
import Darwin
import Combine

public struct HapticFrame {
    public var formants: [Double] = [500, 1500, 2500]
    public var amps: [Double] = [1.0, 0.5, 0.25]
    public var level: Float = 0
    public var voiced = false
    public var f0: Double = 110.0
}

public class HapticEngine: ObservableObject {
    @Published public var isPlaying: Bool = false
    @Published public var currentF0: Double = 0.0
    @Published public var currentF1: Double = 0.0
    @Published public var currentF2: Double = 0.0
    @Published public var level: Double = 0.0
    @Published public var statusMessage: String = "آماده به کار"
    @Published public var isTrackpadConnected: Bool = false

    private var stopRequested = false
    private let hop = 0.010
    private let sampleRate = 16000.0

    // MultitouchSupport dynamic symbols
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    private typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    private var mtLib: UnsafeMutableRawPointer?
    private var createList: CreateList?
    private var getID: GetID?
    private var isBuiltIn: IsBuiltIn?
    private var actuatorCreate: ActuatorCreate?
    private var actuatorOpen: ActuatorOpen?
    private var actuatorClose: ActuatorClose?
    private var actuationCreate: ActuationCreate?
    private var actuationPlay: ActuationPlay?

    private var motor: CFTypeRef?
    private var motorPointer: UnsafeMutableRawPointer?
    private var timebase = mach_timebase_info_data_t()
    private var ticksPerSecond: Double = 1e9

    public init() {
        mach_timebase_info(&timebase)
        ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        loadMultitouch()
        openTrackpadMotor()
    }

    deinit {
        stop()
        if let motor, let actuatorClose {
            _ = actuatorClose(motor)
        }
        if let mtLib {
            dlclose(mtLib)
        }
    }

    private func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let mtLib, let p = dlsym(mtLib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private func loadMultitouch() {
        mtLib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        guard mtLib != nil else { return }
        createList = sym("MTDeviceCreateList", CreateList.self)
        getID = sym("MTDeviceGetDeviceID", GetID.self)
        isBuiltIn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
        actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
        actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self)
        actuatorClose = sym("MTActuatorClose", ActuatorClose.self)
        actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self)
        actuationPlay = sym("MTActuationActuate", ActuationPlay.self)
    }

    public func openTrackpadMotor() {
        guard let createList, let getID, let actuatorCreate, let actuatorOpen, actuationCreate != nil, actuationPlay != nil else {
            DispatchQueue.main.async {
                self.isTrackpadConnected = false
                self.statusMessage = "توابع هپتیک سیستمی در دسترس نیستند"
            }
            return
        }

        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            DispatchQueue.main.async {
                self.isTrackpadConnected = false
                self.statusMessage = "ترک‌پد متصل پیدا نشد"
            }
            return
        }

        var ids: [(id: UInt64, builtIn: Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if getID(dev, &id) == 0 {
                ids.append((id, isBuiltIn?(dev) ?? false))
            }
        }

        for d in ids.sorted(by: { $0.builtIn && !$1.builtIn }) {
            if let ref = actuatorCreate(d.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
                self.motor = ref
                self.motorPointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
                DispatchQueue.main.async {
                    self.isTrackpadConnected = true
                    self.statusMessage = "موتور هپتیک Force Touch فعال است"
                }
                return
            }
        }

        DispatchQueue.main.async {
            self.isTrackpadConnected = false
            self.statusMessage = "موتور هپتیک یافت نشد"
        }
    }

    private func playTone(_ tones: [(hz: Double, amp: Double)], ms: Double, level: Float, intensityMultiplier: Double) {
        guard let motorPointer, !tones.isEmpty else { return }
        let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
        let scaledLevel = min(1.0, max(0.0, Float(Double(level) * intensityMultiplier)))
        let shape: [String: Any] = [
            "BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
            "Tones": tones.map { [
                "Type": "Sine",
                "Amplitude": $0.amp / sum,
                "DurationMS": ms,
                "DelayMS": 0.0,
                "FrequencykHz": $0.hz / 1000.0
            ] }
        ]
        guard let act = actuationCreate?(shape as CFDictionary, 0) else { return }
        _ = actuationPlay?(act, motorPointer, 0, scaledLevel, 0)
        Unmanaged<AnyObject>.fromOpaque(act).release()
    }

    public func stop() {
        stopRequested = true
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentF0 = 0
            self.currentF1 = 0
            self.currentF2 = 0
            self.level = 0
            self.statusMessage = "پخش متوقف شد"
        }
    }

    public func playAudioFile(url: URL, intensity: Double = 1.0, completion: @escaping () -> Void) {
        stopRequested = false
        DispatchQueue.main.async {
            self.isPlaying = true
            self.statusMessage = "در حال تحلیل و انتقال ارتعاش..."
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            guard let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil,
                  let ch = buf.floatChannelData?[0] else {
                DispatchQueue.main.async {
                    self.isPlaying = false
                    self.statusMessage = "خطا در خواندن فایل صوتی"
                    completion()
                }
                return
            }

            let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
            var frames = self.analyseAudio(samples)
            while let first = frames.first, first.level == 0 { frames.removeFirst() }
            while let last = frames.last, last.level == 0 { frames.removeLast() }

            if frames.isEmpty {
                DispatchQueue.main.async {
                    self.isPlaying = false
                    self.statusMessage = "فایل صوتی بدون دیتا است"
                    completion()
                }
                return
            }

            let total = Double(frames.count) * self.hop
            let start = mach_absolute_time()
            var t = 0.0

            while t < total && !self.stopRequested {
                let f = frames[min(frames.count - 1, Int(t / self.hop))]
                var step = 0.005
                if f.level > 0 {
                    if f.voiced {
                        step = 1.0 / max(70.0, f.f0)
                        let tones = self.voiceTones(f)
                        self.playTone(tones, ms: step * 1000.0, level: f.level, intensityMultiplier: intensity)
                        DispatchQueue.main.async {
                            self.currentF0 = f.f0
                            self.currentF1 = f.formants[0]
                            self.currentF2 = f.formants[1]
                            self.level = Double(f.level)
                        }
                    } else {
                        step = 0.004
                        let hiss = (0..<3).map { _ in (Double.random(in: 2700...4100), 1.0) }
                        self.playTone(hiss, ms: step * 1000.0, level: f.level * 0.7, intensityMultiplier: intensity)
                        DispatchQueue.main.async {
                            self.currentF0 = 0
                            self.currentF1 = 3000
                            self.currentF2 = 3800
                            self.level = Double(f.level * 0.7)
                        }
                    }
                }
                t += step
                let target = start + UInt64(t * self.ticksPerSecond)
                let margin = UInt64(0.0015 * self.ticksPerSecond)
                while !self.stopRequested {
                    let n = mach_absolute_time()
                    if n >= target { break }
                    if target - n > margin {
                        usleep(useconds_t(Double(target - n - margin) / self.ticksPerSecond * 1e6))
                    }
                }
            }

            DispatchQueue.main.async {
                self.isPlaying = false
                self.currentF0 = 0
                self.currentF1 = 0
                self.currentF2 = 0
                self.level = 0
                self.statusMessage = self.stopRequested ? "متوقف شد" : "پایان ارتعاش هپتیک"
                completion()
            }
        }
    }

    private func voiceTones(_ f: HapticFrame) -> [(hz: Double, amp: Double)] {
        let w = [f.amps[0], f.amps[1] * 1.8]
        let sum = max(w[0] + w[1], 1e-9)
        return [(f.formants[0], w[0] / sum), (f.formants[1], w[1] / sum)]
    }

    private func lpc(_ x: [Double], order p: Int) -> ([Double], Double) {
        var r = [Double](repeating: 0, count: p + 1)
        for k in 0...p {
            var s = 0.0
            for i in k..<x.count { s += x[i] * x[i - k] }
            r[k] = s
        }
        var a = [Double](repeating: 0, count: p + 1)
        a[0] = 1.0
        guard r[0] > 1e-12 else { return (a, 0) }
        r[0] *= 1.0001
        var e = r[0]
        for i in 1...p {
            var acc = r[i]
            for j in 1..<i { acc += a[j] * r[i - j] }
            let k = -acc / e
            var na = a
            for j in 1..<i { na[j] = a[j] + k * a[i - j] }
            na[i] = k
            a = na
            e *= 1.0 - k * k
        }
        return (a, e)
    }

    private struct ComplexNum {
        var re: Double, im: Double
        static func + (l: ComplexNum, r: ComplexNum) -> ComplexNum { ComplexNum(re: l.re + r.re, im: l.im + r.im) }
        static func - (l: ComplexNum, r: ComplexNum) -> ComplexNum { ComplexNum(re: l.re - r.re, im: l.im - r.im) }
        static func * (l: ComplexNum, r: ComplexNum) -> ComplexNum { ComplexNum(re: l.re * r.re - l.im * r.im, im: l.re * r.im + l.im * r.re) }
        static func / (l: ComplexNum, r: ComplexNum) -> ComplexNum {
            let d = r.re * r.re + r.im * r.im
            return ComplexNum(re: (l.re * r.re + l.im * r.im) / d, im: (l.im * r.re - l.re * r.im) / d)
        }
    }

    private func roots(_ a: [Double]) -> [ComplexNum] {
        let p = a.count - 1
        var z = (0..<p).map { k -> ComplexNum in
            let ang = 2.0 * Double.pi * Double(k) / Double(p) + 0.4
            return ComplexNum(re: 0.9 * cos(ang), im: 0.9 * sin(ang))
        }
        func poly(_ x: ComplexNum) -> ComplexNum {
            var s = ComplexNum(re: 1.0, im: 0.0)
            for k in 1...p { s = s * x + ComplexNum(re: a[k], im: 0.0) }
            return s
        }
        for _ in 0..<300 {
            var moved = 0.0
            for i in 0..<p {
                var d = ComplexNum(re: 1.0, im: 0.0)
                for j in 0..<p where j != i { d = d * (z[i] - z[j]) }
                if d.re == 0 && d.im == 0 { d = ComplexNum(re: 1e-12, im: 0.0) }
                let step = poly(z[i]) / d
                z[i] = z[i] - step
                moved = max(moved, abs(step.re) + abs(step.im))
            }
            if moved < 1e-10 { break }
        }
        return z
    }

    private func analyseAudio(_ x: [Float]) -> [HapticFrame] {
        let win = Int(0.025 * sampleRate), hopN = Int(hop * sampleRate), order = 18
        let hamming = (0..<win).map { 0.54 - 0.46 * cos(2.0 * .pi * Double($0) / Double(win - 1)) }
        var frames: [HapticFrame] = [], rmsList: [Double] = []
        var prev = HapticFrame()
        var i = 0

        while i + win <= x.count {
            let seg = (0..<win).map { Double(x[i + $0]) }
            rmsList.append(sqrt(seg.reduce(0) { $0 + $1 * $1 } / Double(win)))
            var f = prev
            var zc = 0
            for k in 1..<win where (seg[k] >= 0) != (seg[k - 1] >= 0) { zc += 1 }
            var bestLag = 0, bestR = 0.0
            for lag in Int(sampleRate / 300)...Int(sampleRate / 70) where lag < win - 40 {
                var s = 0.0, ea = 0.0, eb = 0.0
                for k in 0..<(win - lag) {
                    s += seg[k] * seg[k + lag]
                    ea += seg[k] * seg[k]
                    eb += seg[k + lag] * seg[k + lag]
                }
                let r = s / max(sqrt(ea * eb), 1e-12)
                if r > bestR { bestR = r; bestLag = lag }
            }
            f.voiced = bestR > 0.35 && Double(zc) / Double(win) < 0.22
            if f.voiced, bestLag > 0 { f.f0 = sampleRate / Double(bestLag) }

            var pe = [Double](repeating: 0, count: win)
            for k in 0..<win { pe[k] = (seg[k] - 0.97 * (k > 0 ? seg[k - 1] : 0)) * hamming[k] }
            let (a, err) = lpc(pe, order: order)
            var cands: [Double] = []
            if err > 0 {
                for z in roots(a) where z.im > 0 {
                    let hz = atan2(z.im, z.re) * sampleRate / (2.0 * .pi)
                    let bw = -log(max(1e-9, sqrt(z.re * z.re + z.im * z.im))) * sampleRate / .pi
                    if hz > 150, hz < 4200, bw < 500 { cands.append(hz) }
                }
            }
            func pick(_ lo: Double, _ hi: Double, near: Double) -> Double? {
                cands.filter { $0 >= lo && $0 <= hi }.min { abs($0 - near) < abs($1 - near) }
            }
            if let f1 = pick(200, 1000, near: prev.formants[0]) { f.formants[0] = f1 }
            if let f2 = pick(max(f.formants[0] + 200, 650), 2700, near: prev.formants[1]) { f.formants[1] = f2 }
            if let f3 = pick(max(f.formants[1] + 300, 1700), 3900, near: prev.formants[2]) { f.formants[2] = f3 }

            if err > 0 {
                f.amps = f.formants.map { hz in
                    let w = 2.0 * Double.pi * hz / sampleRate
                    var re = 0.0, im = 0.0
                    for k in 0...order {
                        re += a[k] * cos(w * Double(k))
                        im -= a[k] * sin(w * Double(k))
                    }
                    return 1.0 / max(sqrt(re * re + im * im), 1e-6)
                }
            }
            frames.append(f)
            prev = f
            i += hopN
        }

        let peak = rmsList.max() ?? 1.0
        for k in frames.indices {
            let rel = rmsList[k] / max(peak, 1e-9)
            frames[k].level = rel < 0.02 ? 0 : Float(min(1.0, pow(rel, 0.45)))
            if frames[k].level == 0 { frames[k].voiced = false }
        }

        func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        let raw = frames
        for k in frames.indices {
            let lo = max(0, k - 2), hi = min(frames.count - 1, k + 2)
            for j in 0..<3 { frames[k].formants[j] = median((lo...hi).map { raw[$0].formants[j] }) }
            frames[k].f0 = min(250, max(70, median((lo...hi).map { raw[$0].f0 })))
        }
        return frames
    }
}
