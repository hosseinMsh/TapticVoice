import Foundation
import AVFoundation
import Combine

public class SpeechBridge: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public var isSynthesizing: Bool = false
    @Published public var isSpeakerPlaying: Bool = false
    @Published public var errorMessage: String? = nil

    private var audioPlayer: AVAudioPlayer?
    private var lastGeneratedUrl: URL?

    public override init() {
        super.init()
    }

    public func synthesize(text: String, speedPct: Int, pitchHz: Int, completion: @escaping (URL?) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
            let outUrl = tempDir.appendingPathComponent("taptic_speech_\(UUID().uuidString).wav")

            // Locate taptic_synth.py (in Bundle resources, or next to executable, or fallback)
            var scriptPath: String?
            if let res = Bundle.main.path(forResource: "taptic_synth", ofType: "py") {
                scriptPath = res
            } else {
                let candidates = [
                    Bundle.main.bundlePath + "/Contents/Resources/taptic_synth.py",
                    FileManager.default.currentDirectoryPath + "/apps/TapticVoice/Sources/Resources/taptic_synth.py",
                    FileManager.default.currentDirectoryPath + "/Sources/Resources/taptic_synth.py"
                ]
                scriptPath = candidates.first { FileManager.default.fileExists(atPath: $0) }
            }

            guard let script = scriptPath else {
                DispatchQueue.main.async {
                    self.isSynthesizing = false
                    self.errorMessage = "اسکریپت سنتز صدا پیدا نشد."
                    completion(nil)
                }
                return
            }

            let pythonBin = "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: pythonBin) ? pythonBin : "/usr/bin/python3")
            p.arguments = [script, outUrl.path, text, String(speedPct), String(pitchHz)]

            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe

            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: data, encoding: .utf8) ?? ""

                if p.terminationStatus == 0 && FileManager.default.fileExists(atPath: outUrl.path) {
                    self.lastGeneratedUrl = outUrl
                    DispatchQueue.main.async {
                        self.isSynthesizing = false
                        completion(outUrl)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isSynthesizing = false
                        self.errorMessage = "خطا در سنتز صدا: \(outStr)"
                        completion(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSynthesizing = false
                    self.errorMessage = error.localizedDescription
                    completion(nil)
                }
            }
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
