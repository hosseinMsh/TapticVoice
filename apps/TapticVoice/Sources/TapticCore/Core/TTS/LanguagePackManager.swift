import Foundation
import Combine

/// Metadata describing an offline TTS language pack (built-in or downloadable).
public struct VoicePack: Identifiable, Equatable {
    public let id: String          // e.g. "fa_IR", "en_US", "de_DE"
    public let titleEN: String
    public let titleFA: String
    public let nativeFlag: String
    public let archiveName: String // Archive folder / tar.bz2 stem on sherpa-onnx tts-models
    public let downloadSizeMB: Double
    public let isBuiltIn: Bool
    public let systemLanguageCode: String

    public var downloadURL: URL? {
        guard !isBuiltIn else { return nil }
        return URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(archiveName).tar.bz2")
    }

    public func localizedTitle(for lang: AppLanguage) -> String {
        lang == .persian ? titleFA : titleEN
    }
}

/// Manages bundled tiny offline voices (Persian + English) and downloadable Piper TTS packs.
public final class LanguagePackManager: NSObject, ObservableObject {
    @Published public private(set) var installedPackIDs: Set<String> = []
    @Published public private(set) var activeDownloads: [String: Double] = [:] // packID -> 0...1
    @Published public var lastError: String? = nil

    public let bridge = SherpaOnnxBridge()
    private let fallbackTTS = SystemTTSFallback()
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    public static let catalog: [VoicePack] = [
        VoicePack(
            id: "fa_IR",
            titleEN: "Persian (Iran) — Tiny Neural",
            titleFA: "فارسی (ایران) — عصبی فشرده",
            nativeFlag: "🇮🇷",
            archiveName: "vits-piper-fa_IR-amir-medium-int8",
            downloadSizeMB: 20.6,
            isBuiltIn: true,
            systemLanguageCode: "fa-IR"
        ),
        VoicePack(
            id: "en_US",
            titleEN: "English (US) — Tiny Neural",
            titleFA: "انگلیسی (آمریکا) — عصبی فشرده",
            nativeFlag: "🇺🇸",
            archiveName: "vits-piper-en_US-amy-low-int8",
            downloadSizeMB: 21.1,
            isBuiltIn: true,
            systemLanguageCode: "en-US"
        ),
        VoicePack(
            id: "ar_JO",
            titleEN: "Arabic (Kareem) — Neural",
            titleFA: "عربی — عصبی",
            nativeFlag: "🇸🇦",
            archiveName: "vits-piper-ar_JO-kareem-medium-int8",
            downloadSizeMB: 21.0,
            isBuiltIn: false,
            systemLanguageCode: "ar-SA"
        ),
        VoicePack(
            id: "tr_TR",
            titleEN: "Turkish (Fettah) — Neural",
            titleFA: "ترکی استانبولی — عصبی",
            nativeFlag: "🇹🇷",
            archiveName: "vits-piper-tr_TR-fettah-medium-int8",
            downloadSizeMB: 21.2,
            isBuiltIn: false,
            systemLanguageCode: "tr-TR"
        ),
        VoicePack(
            id: "fr_FR",
            titleEN: "French (Siwis) — Tiny Neural",
            titleFA: "فرانسوی — عصبی فشرده",
            nativeFlag: "🇫🇷",
            archiveName: "vits-piper-fr_FR-siwis-low-int8",
            downloadSizeMB: 13.3,
            isBuiltIn: false,
            systemLanguageCode: "fr-FR"
        ),
        VoicePack(
            id: "de_DE",
            titleEN: "German (Eva K) — Tiny Neural",
            titleFA: "آلمانی — عصبی فشرده",
            nativeFlag: "🇩🇪",
            archiveName: "vits-piper-de_DE-eva_k-x_low-int8",
            downloadSizeMB: 13.3,
            isBuiltIn: false,
            systemLanguageCode: "de-DE"
        ),
        VoicePack(
            id: "es_ES",
            titleEN: "Spanish (Carlfm) — Tiny Neural",
            titleFA: "اسپانیایی — عصبی فشرده",
            nativeFlag: "🇪🇸",
            archiveName: "vits-piper-es_ES-carlfm-x_low-int8",
            downloadSizeMB: 13.3,
            isBuiltIn: false,
            systemLanguageCode: "es-ES"
        ),
        VoicePack(
            id: "it_IT",
            titleEN: "Italian (Riccardo) — Tiny Neural",
            titleFA: "ایتالیایی — عصبی فشرده",
            nativeFlag: "🇮🇹",
            archiveName: "vits-piper-it_IT-riccardo-x_low-int8",
            downloadSizeMB: 13.3,
            isBuiltIn: false,
            systemLanguageCode: "it-IT"
        ),
        VoicePack(
            id: "ru_RU",
            titleEN: "Russian (Irina) — Neural",
            titleFA: "روسی — عصبی",
            nativeFlag: "🇷🇺",
            archiveName: "vits-piper-ru_RU-irina-medium-int8",
            downloadSizeMB: 21.1,
            isBuiltIn: false,
            systemLanguageCode: "ru-RU"
        ),
        VoicePack(
            id: "zh_CN",
            titleEN: "Chinese Mandarin — Tiny Neural",
            titleFA: "چینی ماندارین — عصبی فشرده",
            nativeFlag: "🇨🇳",
            archiveName: "vits-piper-zh_CN-xiao_ya-medium-int8",
            downloadSizeMB: 14.0,
            isBuiltIn: false,
            systemLanguageCode: "zh-CN"
        )
    ]

    public override init() {
        super.init()
        refreshInstalledPacks()
    }

    /// Directory inside `Application Support` storing downloaded offline TTS voice packs.
    public var appSupportModelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("TapticVoice/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Locates the bundled `Models` folder inside `TapticVoice.app` or local `Vendor/Models` during dev.
    private var bundledModelsDir: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Models", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/apps/TapticVoice/Vendor/Models", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Vendor/Models", isDirectory: true)
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Scans both bundled and downloaded directories and updates `installedPackIDs`.
    public func refreshInstalledPacks() {
        var found = Set<String>()
        for pack in Self.catalog {
            if resolveModelFiles(for: pack.id) != nil {
                found.insert(pack.id)
            }
        }
        // English is always usable via macOS AVSpeechSynthesizer even in minimal test environments
        found.insert("en_US")
        DispatchQueue.main.async {
            self.installedPackIDs = found
        }
    }

    /// Resolves `(modelUrl, tokensUrl, dataDirUrl)` for a given language pack ID.
    public func resolveModelFiles(for packId: String) -> (model: URL, tokens: URL, dataDir: URL)? {
        let searchRoots = [
            bundledModelsDir?.appendingPathComponent(packId, isDirectory: true),
            appSupportModelsDir.appendingPathComponent(packId, isDirectory: true)
        ].compactMap { $0 }

        let sharedDataDir = bundledModelsDir?.appendingPathComponent("espeak-ng-data", isDirectory: true)

        for folder in searchRoots where FileManager.default.fileExists(atPath: folder.path) {
            let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            guard let modelFile = contents.first(where: { $0.pathExtension == "onnx" }),
                  let tokensFile = contents.first(where: { $0.lastPathComponent == "tokens.txt" }) else {
                continue
            }

            let localData = folder.appendingPathComponent("espeak-ng-data", isDirectory: true)
            let dataDir: URL
            if FileManager.default.fileExists(atPath: localData.path) {
                dataDir = localData
            } else if let sharedDataDir, FileManager.default.fileExists(atPath: sharedDataDir.path) {
                dataDir = sharedDataDir
            } else {
                continue
            }
            return (modelFile, tokensFile, dataDir)
        }
        return nil
    }

    /// Synthesizes potentially mixed-script text offline into 16 kHz Float32 mono samples.
    public func synthesizeOffline(text: String, forcedLanguageId: String?, speed: Double) -> [Float]? {
        let segments = TextScriptSegmenter.segment(
            text,
            forcedLanguageId: forcedLanguageId,
            installedLanguageIds: installedPackIDs
        )
        guard !segments.isEmpty else { return nil }

        var pcmChunks: [[Float]] = []
        for seg in segments {
            if let files = resolveModelFiles(for: seg.languageId),
               let samples = bridge.synthesize(
                   languageId: seg.languageId,
                   text: seg.text,
                   modelUrl: files.model,
                   tokensUrl: files.tokens,
                   dataDirUrl: files.dataDir,
                   speed: speed
               ), !samples.isEmpty {
                pcmChunks.append(samples)
            } else {
                let pack = Self.catalog.first { $0.id == seg.languageId }
                let sysCode = pack?.systemLanguageCode ?? "en-US"
                if let sysSamples = fallbackTTS.synthesize(text: seg.text, languageCode: sysCode, speed: speed) {
                    pcmChunks.append(sysSamples)
                }
            }
        }

        guard !pcmChunks.isEmpty else { return nil }
        return AudioResampler.concatenateWithCrossfade(pcmChunks)
    }

    /// Downloads and extracts an additional offline language pack archive into `Application Support`.
    public func downloadPack(_ pack: VoicePack) {
        guard !pack.isBuiltIn, let url = pack.downloadURL else { return }
        guard activeDownloads[pack.id] == nil else { return }

        DispatchQueue.main.async {
            self.activeDownloads[pack.id] = 0.01
            self.lastError = nil
        }

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.taskDescription = pack.id
        downloadTasks[pack.id] = task
        task.resume()
    }

    /// Cancels an active language pack download.
    public func cancelDownload(packId: String) {
        downloadTasks[packId]?.cancel()
        downloadTasks.removeValue(forKey: packId)
        DispatchQueue.main.async {
            self.activeDownloads.removeValue(forKey: packId)
        }
    }

    /// Removes a downloaded language pack from disk and unloads it from memory.
    public func removePack(_ pack: VoicePack) {
        guard !pack.isBuiltIn else { return }
        bridge.unloadEngine(languageId: pack.id)
        let folder = appSupportModelsDir.appendingPathComponent(pack.id, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        refreshInstalledPacks()
    }
}

extension LanguagePackManager: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let packId = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let progress = min(0.95, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        DispatchQueue.main.async {
            self.activeDownloads[packId] = progress
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let packId = downloadTask.taskDescription,
              let pack = Self.catalog.first(where: { $0.id == packId }) else { return }

        let tempExtractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taptic_pack_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempExtractDir)
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: packId)
                self.downloadTasks.removeValue(forKey: packId)
            }
        }

        do {
            try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
            let tarProcess = Process()
            tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tarProcess.arguments = ["-xjf", location.path, "-C", tempExtractDir.path]
            try tarProcess.run()
            tarProcess.waitUntilExit()

            guard tarProcess.terminationStatus == 0 else {
                throw NSError(domain: "TapticVoice", code: Int(tarProcess.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Archive extraction failed."])
            }

            let extractedSubdir = tempExtractDir.appendingPathComponent(pack.archiveName, isDirectory: true)
            let sourceDir = FileManager.default.fileExists(atPath: extractedSubdir.path)
                ? extractedSubdir
                : (try FileManager.default.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil).first ?? tempExtractDir)

            let destDir = appSupportModelsDir.appendingPathComponent(pack.id, isDirectory: true)
            try? FileManager.default.removeItem(at: destDir)
            try FileManager.default.moveItem(at: sourceDir, to: destDir)

            // Deduplicate espeak-ng-data if shared bundled directory exists to save ~25 MB per pack
            if let shared = bundledModelsDir?.appendingPathComponent("espeak-ng-data"),
               FileManager.default.fileExists(atPath: shared.path) {
                try? FileManager.default.removeItem(at: destDir.appendingPathComponent("espeak-ng-data"))
            }

            refreshInstalledPacks()
        } catch {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let packId = task.taskDescription, let error else { return }
        DispatchQueue.main.async {
            self.activeDownloads.removeValue(forKey: packId)
            self.downloadTasks.removeValue(forKey: packId)
            if (error as NSError).code != NSURLErrorCancelled {
                self.lastError = error.localizedDescription
            }
        }
    }
}
