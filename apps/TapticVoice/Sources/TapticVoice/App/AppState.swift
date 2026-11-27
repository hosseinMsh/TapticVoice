import SwiftUI
import AVFoundation
import Combine
import TapticCore

/// Central application coordinator connecting bilingual UI, offline multi-language TTS, DSP, and haptic hardware.
public final class AppState: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @AppStorage("uiLanguage") public var uiLanguageRaw: String = AppLanguage.english.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("preferExternalTrackpad") public var preferExternalTrackpad: Bool = false {
        didSet {
            hapticEngine.reconnect(preferExternal: preferExternalTrackpad)
        }
    }

    @Published public var inputText: String = ""
    @Published public var selectedVoiceMode: String = "auto" // "auto" or pack ID (e.g. "fa_IR", "en_US")
    @Published public var audioConfig = HapticAudioConfig()
    @Published public var isSynthesizing: Bool = false
    @Published public var isSpeakerPlaying: Bool = false
    @Published public var errorBanner: String? = nil
    @Published public var showLanguagePacksSheet: Bool = false

    public let hapticEngine: HapticEngine
    public let packManager = LanguagePackManager()

    private var audioPlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    public var uiLanguage: AppLanguage {
        get { AppLanguage(rawValue: uiLanguageRaw) ?? .english }
        set { uiLanguageRaw = newValue.rawValue }
    }

    public override init() {
        let initialExternal = UserDefaults.standard.bool(forKey: "preferExternalTrackpad")
        self.hapticEngine = HapticEngine(preferExternal: initialExternal)
        super.init()

        self.inputText = L10n.text(.defaultText, lang: uiLanguage)

        hapticEngine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        packManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    public func t(_ key: L10nKey) -> String {
        L10n.text(key, lang: uiLanguage)
    }

    public func toggleUILanguage() {
        let next: AppLanguage = uiLanguage == .english ? .persian : .english
        uiLanguage = next
    }

    public func reconnectTrackpad() {
        let ok = hapticEngine.reconnect(preferExternal: preferExternalTrackpad)
        if !ok {
            errorBanner = t(.errorNoTrackpad)
        } else {
            errorBanner = nil
        }
    }

    public func stopAll() {
        hapticEngine.stop()
        stopSpeakerPreview()
    }

    public func speakOnTrackpad() {
        if hapticEngine.isPlaying {
            hapticEngine.stop()
            return
        }
        stopSpeakerPreview()

        guard hapticEngine.isTrackpadConnected || hapticEngine.reconnect(preferExternal: preferExternalTrackpad) else {
            errorBanner = t(.errorNoTrackpad)
            return
        }

        synthesizeProcessedSamples { [weak self] samples in
            guard let self, let samples else { return }
            self.hapticEngine.play(samples: samples, config: self.audioConfig)
        }
    }

    public func toggleSpeakerPreview() {
        if isSpeakerPlaying {
            stopSpeakerPreview()
            return
        }
        hapticEngine.stop()

        synthesizeProcessedSamples { [weak self] samples in
            guard let self, let samples else { return }
            let previewUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent("taptic_preview_\(UUID().uuidString).wav")
            guard AudioResampler.writeWav16k(samples: samples, to: previewUrl) else {
                self.errorBanner = self.t(.errorSynthesisFailed)
                return
            }
            do {
                let player = try AVAudioPlayer(contentsOf: previewUrl)
                player.delegate = self
                player.prepareToPlay()
                player.play()
                self.audioPlayer = player
                self.isSpeakerPlaying = true
            } catch {
                self.errorBanner = error.localizedDescription
            }
        }
    }

    public func stopSpeakerPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeakerPlaying = false
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeakerPlaying = false
        }
    }

    private func synthesizeProcessedSamples(completion: @escaping ([Float]?) -> Void) {
        let clean = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            errorBanner = t(.errorEmptyText)
            completion(nil)
            return
        }

        errorBanner = nil
        isSynthesizing = true

        let forcedLang = selectedVoiceMode == "auto" ? nil : selectedVoiceMode
        let speed = audioConfig.speechSpeed
        let configCopy = audioConfig

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard var samples = self.packManager.synthesizeOffline(
                text: clean,
                forcedLanguageId: forcedLang,
                speed: speed
            ) else {
                DispatchQueue.main.async {
                    self.isSynthesizing = false
                    self.errorBanner = self.t(.errorSynthesisFailed)
                    completion(nil)
                }
                return
            }

            HapticDSP.master(samples: &samples, config: configCopy, sampleRate: AudioResampler.targetSampleRate)

            DispatchQueue.main.async {
                self.isSynthesizing = false
                completion(samples)
            }
        }
    }
}
