import Foundation
import Darwin
import CSherpaOnnx

/// Memory-safe Swift wrapper dynamically loading `libsherpa-onnx-c-api.dylib` for offline neural TTS.
public final class SherpaOnnxBridge {
    private typealias CreateOfflineTtsFn = @convention(c) (UnsafePointer<SherpaOnnxOfflineTtsConfig>?) -> OpaquePointer?
    private typealias DestroyOfflineTtsFn = @convention(c) (OpaquePointer?) -> Void
    private typealias SampleRateFn = @convention(c) (OpaquePointer?) -> Int32
    private typealias GenerateWithConfigFn = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<SherpaOnnxGenerationConfig>?,
        SherpaOnnxGeneratedAudioProgressCallbackWithArg?,
        UnsafeMutableRawPointer?
    ) -> UnsafePointer<SherpaOnnxGeneratedAudio>?
    private typealias DestroyAudioFn = @convention(c) (UnsafePointer<SherpaOnnxGeneratedAudio>?) -> Void

    private var libHandle: UnsafeMutableRawPointer?
    private var createTts: CreateOfflineTtsFn?
    private var destroyTts: DestroyOfflineTtsFn?
    private var getSampleRate: SampleRateFn?
    private var generateWithConfig: GenerateWithConfigFn?
    private var destroyAudio: DestroyAudioFn?

    private let lock = NSLock()
    private var engines: [String: OpaquePointer] = [:]

    public var isRuntimeAvailable: Bool {
        createTts != nil && generateWithConfig != nil
    }

    public init() {
        loadLibrary()
    }

    deinit {
        lock.lock()
        for (_, ptr) in engines {
            destroyTts?(ptr)
        }
        engines.removeAll()
        lock.unlock()

        if let libHandle {
            dlclose(libHandle)
        }
    }

    private func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let libHandle, let p = dlsym(libHandle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private func loadLibrary() {
        let candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libsherpa-onnx-c-api.dylib"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/libsherpa-onnx-c-api.dylib"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/apps/TapticVoice/Vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let handle = dlopen(url.path, RTLD_NOW) {
                self.libHandle = handle
                self.createTts = sym("SherpaOnnxCreateOfflineTts", CreateOfflineTtsFn.self)
                self.destroyTts = sym("SherpaOnnxDestroyOfflineTts", DestroyOfflineTtsFn.self)
                self.getSampleRate = sym("SherpaOnnxOfflineTtsSampleRate", SampleRateFn.self)
                self.generateWithConfig = sym("SherpaOnnxOfflineTtsGenerateWithConfig", GenerateWithConfigFn.self)
                self.destroyAudio = sym("SherpaOnnxDestroyOfflineTtsGeneratedAudio", DestroyAudioFn.self)
                return
            }
        }
    }

    /// Synthesizes `text` offline using the model files at `modelUrl`, `tokensUrl`, and `dataDirUrl`,
    /// returning 16 kHz Float32 mono PCM samples.
    public func synthesize(
        languageId: String,
        text: String,
        modelUrl: URL,
        tokensUrl: URL,
        dataDirUrl: URL,
        speed: Double
    ) -> [Float]? {
        guard isRuntimeAvailable else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let ttsPtr: OpaquePointer
        if let cached = engines[languageId] {
            ttsPtr = cached
        } else {
            guard let created = createEngine(modelUrl: modelUrl, tokensUrl: tokensUrl, dataDirUrl: dataDirUrl) else {
                return nil
            }
            engines[languageId] = created
            ttsPtr = created
        }

        var genCfg = SherpaOnnxGenerationConfig()
        memset(&genCfg, 0, MemoryLayout<SherpaOnnxGenerationConfig>.size)
        genCfg.sid = 0
        genCfg.speed = Float(max(0.6, min(1.6, speed)))
        genCfg.silence_scale = 0.2

        guard let audioPtr = text.withCString({ cText in
            generateWithConfig?(ttsPtr, cText, &genCfg, nil, nil)
        }) else {
            return nil
        }
        defer { destroyAudio?(audioPtr) }

        let generated = audioPtr.pointee
        guard generated.n > 0, let samplesPtr = generated.samples else {
            return nil
        }

        let rawSamples = Array(UnsafeBufferPointer(start: samplesPtr, count: Int(generated.n)))
        let rate = generated.sample_rate > 0 ? Double(generated.sample_rate) : Double(getSampleRate?(ttsPtr) ?? 22050)
        return AudioResampler.resampleTo16k(samples: rawSamples, sourceRate: rate)
    }

    /// Unloads a cached TTS engine (e.g. when the user deletes a downloaded language pack).
    public func unloadEngine(languageId: String) {
        lock.lock()
        if let ptr = engines.removeValue(forKey: languageId) {
            destroyTts?(ptr)
        }
        lock.unlock()
    }

    private func createEngine(modelUrl: URL, tokensUrl: URL, dataDirUrl: URL) -> OpaquePointer? {
        guard let createTts else { return nil }

        var cfg = SherpaOnnxOfflineTtsConfig()
        memset(&cfg, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)

        return modelUrl.path.withCString { cModel in
            tokensUrl.path.withCString { cTokens in
                dataDirUrl.path.withCString { cDataDir in
                    "".withCString { cEmpty in
                        "cpu".withCString { cProvider in
                            cfg.model.vits.model = cModel
                            cfg.model.vits.lexicon = cEmpty
                            cfg.model.vits.tokens = cTokens
                            cfg.model.vits.data_dir = cDataDir
                            cfg.model.vits.noise_scale = 0.667
                            cfg.model.vits.noise_scale_w = 0.8
                            cfg.model.vits.length_scale = 1.0
                            cfg.model.vits.dict_dir = cEmpty

                            cfg.model.num_threads = 2
                            cfg.model.debug = 0
                            cfg.model.provider = cProvider
                            cfg.max_num_sentences = 1
                            cfg.silence_scale = 0.2

                            return createTts(&cfg)
                        }
                    }
                }
            }
        }
    }
}
