import SwiftUI

public struct MainView: View {
    @StateObject private var hapticEngine = HapticEngine()
    @StateObject private var speechBridge = SpeechBridge()

    @State private var inputText: String = "سلام! من صدای ارتعاش موتور ترک‌پد مک‌بوک شما هستم. با لرزش شیشه صحبت می‌کنم."
    @State private var pitchHz: Double = 0.0
    @State private var speedPct: Double = 0.0
    @State private var intensity: Double = 1.0
    @State private var hapticMastering: Bool = true
    @State private var currentWavUrl: URL? = nil

    private let samplePhrases = [
        "سلام! این ارتعاش هپتیک ترک‌پد مک‌بوک است.",
        "با لرزش شیشه بدون نیاز به بلندگو صحبت می‌کنم.",
        "هوش مصنوعی و سنتز صوتی فورمنت‌ها در بازه ۱۰۰ تا ۴۰۰۰ هرتز."
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // App Icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: .purple.opacity(0.3), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("TapticVoice")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Studio")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.18))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }
                    Text("سنتز گفتار فارسی از طریق ارتعاش شیشه ترک‌پد Force Touch")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Hardware Status Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(hapticEngine.isTrackpadConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(hapticEngine.isTrackpadConnected ? "موتور هپتیک متصل است" : "در انتظار اتصال ترک‌پد")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(hapticEngine.isTrackpadConnected ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(hapticEngine.isTrackpadConnected ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
            .padding(.horizontal, 4)

            // Main Content Area (Text Area + Controls)
            HStack(alignment: .top, spacing: 16) {
                // Left Column: Text Input & Presets
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        // Presets
                        HStack(spacing: 6) {
                            ForEach(0..<samplePhrases.count, id: \.self) { idx in
                                Button(action: { inputText = samplePhrases[idx] }) {
                                    Text("نمونه \(idx + 1)")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        Text("متن پیام فارسی")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    // Text Editor Card
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $inputText)
                            .font(.system(size: 13, weight: .regular))
                            .multilineTextAlignment(.trailing)
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        Text("\(inputText.count) نویسه")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                    .frame(minHeight: 130)

                    // Waveform Visualizer
                    WaveformVisualizer(
                        hapticEngine: hapticEngine,
                        isPreviewPlaying: speechBridge.isSpeakerPlaying
                    )
                }
                .frame(maxWidth: .infinity)

                // Right Column: Controls
                VStack(spacing: 12) {
                    ControlsView(
                        pitchHz: $pitchHz,
                        speedPct: $speedPct,
                        intensity: $intensity,
                        hapticMastering: $hapticMastering
                    )
                }
                .frame(width: 280)
            }

            // Bottom Action Bar
            HStack(spacing: 12) {
                // Secondary Audio Preview Button
                Button(action: handleSpeakerPreview) {
                    HStack(spacing: 6) {
                        if speechBridge.isSpeakerPlaying {
                            Image(systemName: "stop.fill")
                        } else {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        Text(speechBridge.isSpeakerPlaying ? "توقف پیش‌نمایش" : "پیش‌نمایش در بلندگو")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(speechBridge.isSynthesizing || hapticEngine.isPlaying)
                .keyboardShortcut("p", modifiers: .command)

                // Primary Play on Trackpad Button
                Button(action: handlePlayTrackpad) {
                    HStack(spacing: 8) {
                        if speechBridge.isSynthesizing {
                            ProgressView()
                                .controlSize(.small)
                            Text("در حال سنتز عصبی...")
                                .font(.system(size: 13, weight: .semibold))
                        } else if hapticEngine.isPlaying {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 16))
                            Text("توقف ارتعاش ترک‌پد")
                                .font(.system(size: 13, weight: .bold))
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 14))
                            Text("پخش روی ترک‌پد مک‌بوک (ویبره هپتیک)")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: hapticEngine.isPlaying ? [.red, .orange] : [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .purple.opacity(0.3), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }

            // Footer Tips
            HStack {
                Text("نکته: مک‌بوک را روی میز چوبی قرار دهید و در حین صحبت دست‌ها را از روی شیشه بردارید تا حداکثر وضوح را بشنوید.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("میانبرها: ⌘↵ پخش ترک‌پد | ⌘P پیش‌نمایش | Esc توقف")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private func handlePlayTrackpad() {
        if hapticEngine.isPlaying {
            hapticEngine.stop()
            return
        }
        speechBridge.stopSpeakerPreview()

        speechBridge.synthesize(
            text: inputText,
            speedPct: Int(speedPct),
            pitchHz: Int(pitchHz),
            hapticMastering: hapticMastering
        ) { url in
            guard let url = url else { return }
            self.currentWavUrl = url
            self.hapticEngine.playAudioFile(url: url, intensity: self.intensity) {}
        }
    }

    private func handleSpeakerPreview() {
        if speechBridge.isSpeakerPlaying {
            speechBridge.stopSpeakerPreview()
            return
        }
        hapticEngine.stop()

        speechBridge.synthesize(
            text: inputText,
            speedPct: Int(speedPct),
            pitchHz: Int(pitchHz),
            hapticMastering: hapticMastering
        ) { url in
            guard let url = url else { return }
            self.currentWavUrl = url
            self.speechBridge.playSpeakerPreview(url: url)
        }
    }
}

// Visual Effect View for native macOS vibrancy
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode

    public init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
