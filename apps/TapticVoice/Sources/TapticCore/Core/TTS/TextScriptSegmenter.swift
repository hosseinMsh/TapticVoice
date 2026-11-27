import Foundation
import NaturalLanguage

/// A contiguous chunk of text tagged with its resolved offline TTS language pack ID.
public struct TextSegment: Equatable {
    public let text: String
    public let languageId: String

    public init(text: String, languageId: String) {
        self.text = text
        self.languageId = languageId
    }
}

/// Segments mixed-script and multi-language text into contiguous chunks routed to installed TTS voices.
public enum TextScriptSegmenter {
    private enum ScriptFamily: Equatable {
        case arabicPersian
        case latin
        case cyrillic
        case cjk
    }

    /// Splits `input` into contiguous segments mapped to installed voice IDs.
    /// If `forcedLanguageId` is non-nil, returns the entire text as a single segment for that voice.
    public static func segment(
        _ input: String,
        forcedLanguageId: String? = nil,
        installedLanguageIds: Set<String> = ["fa_IR", "en_US"]
    ) -> [TextSegment] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let forced = forcedLanguageId {
            return [TextSegment(text: trimmed, languageId: forced)]
        }

        var rawChunks: [(text: String, family: ScriptFamily?)] = []
        var currentText = ""
        var currentFamily: ScriptFamily? = nil

        for scalar in trimmed.unicodeScalars {
            let detected = classifyScript(scalar)
            if let family = detected {
                if currentFamily == nil {
                    currentFamily = family
                } else if currentFamily != family {
                    let flush = currentText.trimmingCharacters(in: .whitespaces)
                    if !flush.isEmpty {
                        rawChunks.append((flush, currentFamily))
                    }
                    currentText = ""
                    currentFamily = family
                }
            }
            currentText.unicodeScalars.append(scalar)
        }

        let tail = currentText.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            rawChunks.append((tail, currentFamily))
        }

        return rawChunks.map { chunk in
            let resolved = resolveLanguage(for: chunk.text, family: chunk.family, installed: installedLanguageIds)
            return TextSegment(text: chunk.text, languageId: resolved)
        }
    }

    private static func classifyScript(_ scalar: Unicode.Scalar) -> ScriptFamily? {
        let v = scalar.value
        if CharacterSet.whitespacesAndNewlines.contains(scalar) ||
            CharacterSet.punctuationCharacters.contains(scalar) ||
            CharacterSet.decimalDigits.contains(scalar) ||
            CharacterSet.symbols.contains(scalar) {
            return nil
        }

        if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) ||
            (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) {
            return .arabicPersian
        }
        if (0x0400...0x04FF).contains(v) {
            return .cyrillic
        }
        if (0x4E00...0x9FFF).contains(v) {
            return .cjk
        }
        if (0x0041...0x007A).contains(v) || (0x00C0...0x024F).contains(v) {
            return .latin
        }
        return nil
    }

    private static func resolveLanguage(
        for text: String,
        family: ScriptFamily?,
        installed: Set<String>
    ) -> String {
        switch family {
        case .cyrillic:
            return installed.contains("ru_RU") ? "ru_RU" : "en_US"
        case .cjk:
            return installed.contains("zh_CN") ? "zh_CN" : "en_US"
        case .arabicPersian:
            // Distinct Persian characters (پ چ ژ گ ک ی) immediately select Persian
            let persianScalars: Set<UInt32> = [0x067E, 0x0686, 0x0698, 0x06AF, 0x06A9, 0x06CC]
            if text.unicodeScalars.contains(where: { persianScalars.contains($0.value) }) {
                return installed.contains("fa_IR") ? "fa_IR" : "ar_JO"
            }
            if installed.contains("ar_JO") {
                let rec = NLLanguageRecognizer()
                rec.processString(text)
                if rec.dominantLanguage == .arabic {
                    return "ar_JO"
                }
            }
            return installed.contains("fa_IR") ? "fa_IR" : "ar_JO"
        case .latin:
            let rec = NLLanguageRecognizer()
            rec.processString(text)
            if let lang = rec.dominantLanguage {
                switch lang {
                case .turkish where installed.contains("tr_TR"): return "tr_TR"
                case .french where installed.contains("fr_FR"): return "fr_FR"
                case .german where installed.contains("de_DE"): return "de_DE"
                case .spanish where installed.contains("es_ES"): return "es_ES"
                case .italian where installed.contains("it_IT"): return "it_IT"
                default: break
                }
            }
            return "en_US"
        case nil:
            return installed.contains("en_US") ? "en_US" : "fa_IR"
        }
    }
}
