import SwiftUI
import AppKit
import TapticCore

/// Primary macOS workspace view for TapticVoice Studio.
public struct MainView: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        VStack(spacing: 14) {
            headerBar

            if let error = state.errorBanner {
                errorBannerView(error)
            }

            HStack(alignment: .top, spacing: 16) {
                leftWorkspaceColumn
                ControlsPanel()
                    .frame(width: 285)
            }

            actionBar
            footerBar
        }
        .padding(18)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        .sheet(isPresented: $state.showLanguagePacksSheet) {
            LanguagePacksSheet()
                .environmentObject(state)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 19))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(color: .purple.opacity(0.28), radius: 5, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.t(.appName))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(state.t(.offlineReadyBadge))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.14))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
                Text(state.t(.appTagline))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Language packs button
            Button {
                state.showLanguagePacksSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                    Text("\(state.t(.languagePacksButton)) (\(state.packManager.installedPackIDs.count))")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Live EN / FA UI switcher
            Button {
                state.toggleUILanguage()
            } label: {
                Text(state.uiLanguage == .english ? "فارسی" : "English")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Hardware status pill (tap to reconnect)
            Button {
                state.reconnectTrackpad()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.hapticEngine.isTrackpadConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(state.hapticEngine.isTrackpadConnected ? state.t(.motorConnected) : state.t(.motorDisconnected))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(state.hapticEngine.isTrackpadConnected ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(state.hapticEngine.isTrackpadConnected ? Color.green.opacity(0.1) : Color.orange.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help(state.t(.reconnectMotor))
        }
    }

    private var leftWorkspaceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(state.t(.textSectionTitle))
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                // Voice Mode Picker (Auto or specific installed offline pack)
                Picker(state.t(.speechModeLabel), selection: $state.selectedVoiceMode) {
                    Text(state.t(.autoMultiLangMode)).tag("auto")
                    ForEach(LanguagePackManager.catalog.filter { state.packManager.installedPackIDs.contains($0.id) }) { pack in
                        Text("\(pack.nativeFlag) \(pack.localizedTitle(for: state.uiLanguage))")
                            .tag(pack.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 210)
            }

            // Sample phrases + clear bar
            HStack(spacing: 6) {
                samplePill(state.t(.sample1Label), text: state.t(.sample1Text))
                samplePill(state.t(.sample2Label), text: state.t(.sample2Text))
                samplePill(state.t(.sample3Label), text: state.t(.sample3Text))
                Spacer()
                if !state.inputText.isEmpty {
                    Button(state.t(.clearText)) {
                        state.inputText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                }
            }

            // Text Editor
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $state.inputText)
                    .font(.system(size: 13.5))
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text("\(state.inputText.count) \(state.t(.charCountSuffix))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .frame(minHeight: 155)

            WaveformVisualizer()
        }
        .frame(maxWidth: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                state.toggleSpeakerPreview()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isSpeakerPlaying ? "stop.fill" : "speaker.wave.2.fill")
                    Text(state.isSpeakerPlaying ? state.t(.stopPreviewButton) : state.t(.previewButton))
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(state.isSynthesizing)

            Button {
                state.speakOnTrackpad()
            } label: {
                HStack(spacing: 8) {
                    if state.isSynthesizing {
                        ProgressView().controlSize(.small)
                        Text(state.t(.synthesizingStatus))
                            .font(.system(size: 13, weight: .semibold))
                    } else if state.hapticEngine.isPlaying {
                        Image(systemName: "stop.circle.fill")
                        Text(state.t(.stopTrackpadButton))
                            .font(.system(size: 13, weight: .bold))
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(state.t(.playTrackpadButton))
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: state.hapticEngine.isPlaying ? [.red, .orange] : [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .purple.opacity(0.28), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(state.isSynthesizing)
        }
    }

    private var footerBar: some View {
        HStack {
            Text(state.t(.tipFooter))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(state.t(.shortcutsFooter))
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.75))
        }
    }

    private func samplePill(_ label: String, text: String) -> some View {
        Button {
            state.inputText = text
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func errorBannerView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 11.5))
            Spacer()
            Button {
                state.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Native AppKit `NSVisualEffectView` wrapper providing translucent macOS window vibrancy.
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
