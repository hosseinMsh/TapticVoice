import Foundation
import Darwin

/// Safe dynamic wrapper over Apple's private `MultitouchSupport.framework` haptic actuator APIs.
public final class MultitouchBridge {
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

    public private(set) var isConnected: Bool = false
    public private(set) var isBuiltInTrackpad: Bool = true

    public init() {
        loadFramework()
    }

    deinit {
        closeMotor()
        if let mtLib {
            dlclose(mtLib)
        }
    }

    private func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let mtLib, let ptr = dlsym(mtLib, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    private func loadFramework() {
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

    /// Discovers and opens either the built-in trackpad or an external Magic Trackpad 2+.
    @discardableResult
    public func connect(preferExternal: Bool) -> Bool {
        closeMotor()

        guard let createList, let getID, let actuatorCreate, let actuatorOpen,
              actuationCreate != nil, actuationPlay != nil else {
            return false
        }

        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            return false
        }

        var candidates: [(id: UInt64, builtIn: Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var devID: UInt64 = 0
            if getID(dev, &devID) == 0 {
                candidates.append((devID, isBuiltIn?(dev) ?? false))
            }
        }

        let ordered: [(id: UInt64, builtIn: Bool)]
        if preferExternal {
            ordered = candidates.sorted { !$0.builtIn && $1.builtIn }
        } else {
            ordered = candidates.sorted { $0.builtIn && !$1.builtIn }
        }

        for dev in ordered {
            if let ref = actuatorCreate(dev.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
                self.motor = ref
                self.motorPointer = Unmanaged.passUnretained(ref as AnyObject).toOpaque()
                self.isConnected = true
                self.isBuiltInTrackpad = dev.builtIn
                return true
            }
        }

        return false
    }

    /// Closes any currently opened actuator handle cleanly.
    public func closeMotor() {
        if let motor, let actuatorClose {
            _ = actuatorClose(motor)
        }
        motor = nil
        motorPointer = nil
        isConnected = false
    }

    /// Triggers one multi-tone haptic actuation pulse on the trackpad motor.
    public func playTones(_ tones: [(hz: Double, amp: Double)], durationMs: Double, strength: Float) {
        guard let motorPointer, let actuationCreate, let actuationPlay, !tones.isEmpty else { return }
        let clampedStrength = min(1.0, max(0.0, strength))
        let totalAmp = max(tones.reduce(0.0) { $0 + $1.amp }, 1e-4)

        let shape: [String: Any] = [
            "BaseWaveform": [
                "Type": "Gaussian",
                "Amplitude": 0.0,
                "DurationMS": durationMs
            ],
            "Tones": tones.map { tone in
                [
                    "Type": "Sine",
                    "Amplitude": tone.amp / totalAmp,
                    "DurationMS": durationMs,
                    "DelayMS": 0.0,
                    "FrequencykHz": min(4.2, max(0.07, tone.hz / 1000.0))
                ]
            }
        ]

        guard let actuation = actuationCreate(shape as CFDictionary, 0) else { return }
        _ = actuationPlay(actuation, motorPointer, 0, clampedStrength, 0)
        Unmanaged<AnyObject>.fromOpaque(actuation).release()
    }
}
