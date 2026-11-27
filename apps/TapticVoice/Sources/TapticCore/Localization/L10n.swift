import SwiftUI

/// Supported user interface languages for TapticVoice Studio.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case persian = "fa"
    case english = "en"

    public var id: String { rawValue }

    /// Native display badge label shown in the language toggle.
    public var toggleLabel: String {
        switch self {
        case .persian: return "فا"
        case .english: return "EN"
        }
    }

    /// Layout direction required by SwiftUI for the selected language.
    public var layoutDirection: LayoutDirection {
        switch self {
        case .persian: return .rightToLeft
        case .english: return .leftToRight
        }
    }
}

/// Centralized type-safe localization keys enforcing parity between English and Persian.
public enum L10nKey: String, CaseIterable {
    // Header & status
    case appName
    case appTagline
    case motorConnected
    case motorDisconnected
    case reconnectMotor
    case languagePacksButton
    case offlineReadyBadge

    // Text editor & presets
    case textSectionTitle
    case speechModeLabel
    case autoMultiLangMode
    case clearText
    case sample1Label
    case sample2Label
    case sample3Label
    case sample1Text
    case sample2Text
    case sample3Text
    case defaultText
    case charCountSuffix

    // Visualizer
    case visualizerActive
    case visualizerIdle
    case spectrumRangeLabel

    // Controls panel
    case acousticPresetTitle
    case presetClear
    case presetLoud
    case presetTactile
    case presetCustom
    case pitchControl
    case speedControl
    case clarityControl
    case intensityControl
    case compressionControl
    case externalTrackpadToggle
    case externalTrackpadHint
    case resetDefaults

    // Actions & errors
    case previewButton
    case stopPreviewButton
    case playTrackpadButton
    case synthesizingStatus
    case stopTrackpadButton
    case tipFooter
    case shortcutsFooter
    case errorEmptyText
    case errorSynthesisFailed
    case errorNoTrackpad

    // Language packs sheet
    case packsSheetTitle
    case packsSheetSubtitle
    case builtInSectionTitle
    case downloadableSectionTitle
    case alwaysAvailableBadge
    case installedBadge
    case downloadButton
    case downloadingLabel
    case removeButton
    case doneButton
    case persianVoiceTitle
    case englishVoiceTitle
}

/// Provides localized UI strings for English and Persian.
public enum L10n {
    /// Returns the localized string for a key in the given language.
    public static func text(_ key: L10nKey, lang: AppLanguage) -> String {
        switch lang {
        case .english:
            return en[key] ?? key.rawValue
        case .persian:
            return fa[key] ?? key.rawValue
        }
    }

    public static let en: [L10nKey: String] = [
        .appName: "TapticVoice",
        .appTagline: "Offline Haptic Acoustic Speech on MacBook Trackpad",
        .motorConnected: "Haptic Motor Ready",
        .motorDisconnected: "Trackpad Not Found",
        .reconnectMotor: "Reconnect",
        .languagePacksButton: "Languages",
        .offlineReadyBadge: "100% Offline",

        .textSectionTitle: "Message",
        .speechModeLabel: "Voice Mode",
        .autoMultiLangMode: "Auto (Mixed EN / FA)",
        .clearText: "Clear",
        .sample1Label: "Persian",
        .sample2Label: "English",
        .sample3Label: "Mixed",
        .sample1Text: "سلام! من صدای هپتیک شیشه ترک‌پد مک‌بوک شما هستم.",
        .sample2Text: "Hello! Your MacBook trackpad is speaking without any speaker.",
        .sample3Text: "سلام! اپلیکیشن TapticVoice کاملاً آفلاین روی مک‌بوک اجرا می‌شود.",
        .defaultText: "Hello! سلام! I am your MacBook Force Touch trackpad speaking completely offline.",
        .charCountSuffix: "chars",

        .visualizerActive: "Synthesizing Haptic Resonance",
        .visualizerIdle: "Standby (100 Hz – 4 kHz)",
        .spectrumRangeLabel: "100 Hz – 4 kHz",

        .acousticPresetTitle: "Acoustic Profile",
        .presetClear: "Clear",
        .presetLoud: "Loud",
        .presetTactile: "Tactile",
        .presetCustom: "Custom",
        .pitchControl: "Pitch Shift",
        .speedControl: "Speech Speed",
        .clarityControl: "Formant Clarity (F₂)",
        .intensityControl: "Motor Intensity",
        .compressionControl: "Loudness Boost (DSP)",
        .externalTrackpadToggle: "Prefer External Magic Trackpad",
        .externalTrackpadHint: "Use Magic Trackpad 2+ instead of built-in",
        .resetDefaults: "Reset",

        .previewButton: "Speaker Preview",
        .stopPreviewButton: "Stop Preview",
        .playTrackpadButton: "Speak on Trackpad",
        .synthesizingStatus: "Synthesizing Offline...",
        .stopTrackpadButton: "Stop Trackpad",
        .tipFooter: "Tip: Place your MacBook on a wooden desk and keep hands off the glass for loudest sound.",
        .shortcutsFooter: "⌘↵ Trackpad  •  ⌘P Preview  •  Esc Stop",
        .errorEmptyText: "Please enter some text first.",
        .errorSynthesisFailed: "Offline synthesis failed for the selected language.",
        .errorNoTrackpad: "No Force Touch trackpad actuator detected.",

        .packsSheetTitle: "Offline Voice Languages",
        .packsSheetSubtitle: "Persian and English work offline out-of-the-box. Download additional languages once to use offline anytime.",
        .builtInSectionTitle: "Built-in Tiny Voices",
        .downloadableSectionTitle: "Downloadable Offline Packs",
        .alwaysAvailableBadge: "Built-in",
        .installedBadge: "Downloaded",
        .downloadButton: "Download",
        .downloadingLabel: "Downloading...",
        .removeButton: "Remove",
        .doneButton: "Done",
        .persianVoiceTitle: "Persian (Iran) — Tiny Neural",
        .englishVoiceTitle: "English (US) — Tiny Neural"
    ]

    public static let fa: [L10nKey: String] = [
        .appName: "TapticVoice",
        .appTagline: "تبدیل آفلاین متن به صوت هپتیک روی ترک‌پد مک‌بوک",
        .motorConnected: "موتور هپتیک آماده",
        .motorDisconnected: "ترک‌پد یافت نشد",
        .reconnectMotor: "اتصال مجدد",
        .languagePacksButton: "زبان‌ها",
        .offlineReadyBadge: "کاملاً آفلاین",

        .textSectionTitle: "متن پیام",
        .speechModeLabel: "حالت صدا",
        .autoMultiLangMode: "خودکار (ترکیبی فارسی / انگلیسی)",
        .clearText: "پاک کردن",
        .sample1Label: "فارسی",
        .sample2Label: "انگلیسی",
        .sample3Label: "ترکیبی",
        .sample1Text: "سلام! من صدای هپتیک شیشه ترک‌پد مک‌بوک شما هستم.",
        .sample2Text: "Hello! Your MacBook trackpad is speaking without any speaker.",
        .sample3Text: "سلام! اپلیکیشن TapticVoice کاملاً آفلاین روی مک‌بوک اجرا می‌شود.",
        .defaultText: "سلام! من صدای ارتعاش ترک‌پد مک‌بوک هستم و کاملاً آفلاین کار می‌کنم.",
        .charCountSuffix: "نویسه",

        .visualizerActive: "در حال بازتولید رزونانس هپتیک",
        .visualizerIdle: "آماده‌باش (۱۰۰ تا ۴۰۰۰ هرتز)",
        .spectrumRangeLabel: "۱۰۰ Hz – ۴ kHz",

        .acousticPresetTitle: "پروفایل آکوستیک",
        .presetClear: "شفاف",
        .presetLoud: "بلند",
        .presetTactile: "لرزشی",
        .presetCustom: "دستی",
        .pitchControl: "زیر و بمی صدا (Pitch)",
        .speedControl: "سرعت گفتار",
        .clarityControl: "وضوح حروف (F₂)",
        .intensityControl: "شدت موتور هپتیک",
        .compressionControl: "تقویت بلندی صدا (DSP)",
        .externalTrackpadToggle: "استفاده از Magic Trackpad خارجی",
        .externalTrackpadHint: "اولویت با ترک‌پد مجزا به جای ترک‌پد داخلی",
        .resetDefaults: "بازنشانی",

        .previewButton: "پخش در بلندگو",
        .stopPreviewButton: "توقف پیش‌نمایش",
        .playTrackpadButton: "پخش روی ترک‌پد",
        .synthesizingStatus: "در حال پردازش آفلاین...",
        .stopTrackpadButton: "توقف ترک‌پد",
        .tipFooter: "نکته: مک‌بوک را روی میز چوبی قرار دهید و دست‌ها را از شیشه بردارید تا صدایی رساتر بشنوید.",
        .shortcutsFooter: "⌘↵ ترک‌پد  •  ⌘P پیش‌نمایش  •  Esc توقف",
        .errorEmptyText: "لطفاً ابتدا متنی وارد کنید.",
        .errorSynthesisFailed: "تولید آفلاین صدا برای زبان انتخاب‌شده ناموفق بود.",
        .errorNoTrackpad: "موتور هپتیک Force Touch پیدا نشد.",

        .packsSheetTitle: "بسته‌های صوتی آفلاین",
        .packsSheetSubtitle: "زبان‌های فارسی و انگلیسی به صورت پیش‌فرض و آفلاین درون برنامه هستند. سایر زبان‌ها را یک‌بار دانلود کنید تا همیشه آفلاین اجرا شوند.",
        .builtInSectionTitle: "صداهای پیش‌فرض (داخلی)",
        .downloadableSectionTitle: "زبان‌های قابل دانلود",
        .alwaysAvailableBadge: "داخلی",
        .installedBadge: "دانلود شده",
        .downloadButton: "دانلود",
        .downloadingLabel: "در حال دانلود...",
        .removeButton: "حذف",
        .doneButton: "بستن",
        .persianVoiceTitle: "فارسی (ایران) — عصبی فشرده",
        .englishVoiceTitle: "انگلیسی (آمریکا) — عصبی فشرده"
    ]
}
