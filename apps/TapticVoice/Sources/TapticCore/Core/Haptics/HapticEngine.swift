import Foundation
import Darwin

/// Thread-safe snapshot of live haptic playback telemetry polled by the UI at ~30 Hz.
public struct TelemetrySnapshot: Equatable {
    public var isPlaying: Bool = false
    public var f0: Double = 0.0
    public var f1: Double = 0.0
    public var f2: Double = 0.0
    public var level: Double = 0.0
    public var actuations: UInt64 = 0

    public init() {}
}

/// Real-time haptic voice playback engine driving the Force Touch trackpad actuator.
public final class HapticEngine: ObservableObject {
    @Published public var isPlaying: Bool = false
    @Published public var isTrackpadConnected: Bool = false
    @Published public var isBuiltInTrackpad: Bool = true

    private let bridge = MultitouchBridge()
    private let telemetryLock = NSLock()
    private var snapshot = TelemetrySnapshot()

    private var stopRequested = false
    private var timebase = mach_timebase_info_data_t()
    private var ticksPerSecond: Double = 1e9

    public init(preferExternal: Bool = false) {
        mach_timebase_info(&timebase)
        ticksPerSecond = 1e9 * Double(timebase.denom) / Double(timebase.numer)
        reconnect(preferExternal: preferExternal)
    }

    deinit {
        stop()
        bridge.closeMotor()
    }

    /// Re-scans IOKit multitouch actuators (built-in trackpad or external Magic Trackpad).
    @discardableResult
    public func reconnect(preferExternal: Bool) -> Bool {
        let connected = bridge.connect(preferExternal: preferExternal)
        let builtIn = bridge.isBuiltInTrackpad
        DispatchQueue.main.async {
            self.isTrackpadConnected = connected
            self.isBuiltInTrackpad = builtIn
        }
        return connected
    }

    /// Reads the latest lock-protected telemetry snapshot without blocking the audio thread.
    public func readTelemetry() -> TelemetrySnapshot {
        telemetryLock.lock()
        let copy = snapshot
        telemetryLock.unlock()
        return copy
    }

    private func updateTelemetry(_ block: (inout TelemetrySnapshot) -> Void) {
        telemetryLock.lock()
        block(&snapshot)
        telemetryLock.unlock()
    }

    /// Immediately stops any active haptic playback.
    public func stop() {
        stopRequested = true
        updateTelemetry {
            $0.isPlaying = false
            $0.f0 = 0
            $0.f1 = 0
            $0.f2 = 0
            $0.level = 0
        }
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    /// Analyzes in-memory 16 kHz Float32 mono samples and actuates the trackpad motor in real time.
    public func play(samples: [Float], config: HapticAudioConfig, completion: (() -> Void)? = nil) {
        guard !samples.isEmpty else {
            completion?()
            return
        }

        stopRequested = false
        updateTelemetry {
            $0.isPlaying = true
            $0.actuations = 0
        }
        DispatchQueue.main.async {
            self.isPlaying = true
        }

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }

            let frames = LPCAnalyzer.analyze(samples, trimSilence: true)
            guard !frames.isEmpty else {
                self.finishPlayback(completion: completion)
                return
            }

            let pitchRatio = pow(2.0, config.pitchShiftSemitones / 12.0)
            let totalDuration = Double(frames.count) * LPCAnalyzer.hopSeconds
            let startTicks = mach_absolute_time()
            var elapsed = 0.0

            while elapsed < totalDuration && !self.stopRequested {
                let idx = min(frames.count - 1, Int(elapsed / LPCAnalyzer.hopSeconds))
                let frame = frames[idx]
                var step = 0.005

                if frame.level > 0 {
                    if frame.voiced {
                        let shiftedF0 = min(300.0, max(70.0, frame.f0 * pitchRatio))
                        step = 1.0 / shiftedF0
                        let tones = LPCAnalyzer.voiceTones(for: frame, clarity: config.formantClarity)
                        let strength = Float(Double(frame.level) * config.motorIntensity)
                        self.bridge.playTones(tones, durationMs: step * 1000.0, strength: strength)

                        self.updateTelemetry {
                            $0.f0 = shiftedF0
                            $0.f1 = frame.formants[0]
                            $0.f2 = frame.formants[1]
                            $0.level = Double(frame.level)
                            $0.actuations &+= 1
                        }
                    } else {
                        step = 0.004
                        let hissTones: [(hz: Double, amp: Double)] = (0..<3).map { _ in
                            (Double.random(in: 2700.0...4050.0), 1.0)
                        }
                        let strength = Float(Double(frame.level) * 0.72 * config.motorIntensity)
                        self.bridge.playTones(hissTones, durationMs: step * 1000.0, strength: strength)

                        self.updateTelemetry {
                            $0.f0 = 0
                            $0.f1 = 2900
                            $0.f2 = 3800
                            $0.level = Double(frame.level) * 0.72
                            $0.actuations &+= 1
                        }
                    }
                }

                elapsed += step
                self.waitUntil(startTicks + UInt64(elapsed * self.ticksPerSecond))
            }

            self.finishPlayback(completion: completion)
        }
    }

    private func waitUntil(_ targetTicks: UInt64) {
        let spinMargin = UInt64(0.0015 * ticksPerSecond)
        while !stopRequested {
            let nowTicks = mach_absolute_time()
            if nowTicks >= targetTicks { return }
            if targetTicks - nowTicks > spinMargin {
                let sleepUs = Double(targetTicks - nowTicks - spinMargin) / ticksPerSecond * 1_000_000.0
                usleep(useconds_t(max(100, sleepUs)))
            }
        }
    }

    private func finishPlayback(completion: (() -> Void)?) {
        updateTelemetry {
            $0.isPlaying = false
            $0.f0 = 0
            $0.f1 = 0
            $0.f2 = 0
            $0.level = 0
        }
        DispatchQueue.main.async {
            self.isPlaying = false
            completion?()
        }
    }
}
