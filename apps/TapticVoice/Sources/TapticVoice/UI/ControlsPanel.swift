import SwiftUI
import TapticCore

/// Clean acoustic preset & fine-tuning panel for trackpad voice clarity and loudness.
public struct ControlsPanel: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preset picker + reset
            HStack {
                Text(state.t(.acousticPresetTitle))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(state.t(.resetDefaults)) {
                    state.audioConfig = HapticAudioConfig()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentColor)
            }

            Picker("", selection: Binding(
                get: { state.audioConfig.preset },
                set: { state.audioConfig.applyPreset($0) }
            )) {
                Text(state.t(.presetClear)).tag(AcousticPreset.clear)
                Text(state.t(.presetLoud)).tag(AcousticPreset.loud)
                Text(state.t(.presetTactile)).tag(AcousticPreset.tactile)
                Text(state.t(.presetCustom)).tag(AcousticPreset.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider().opacity(0.35)

            // Speed
            sliderRow(
                title: state.t(.speedControl),
                valueLabel: String(format: "%.2fx", state.audioConfig.speechSpeed),
                tint: .blue,
                value: $state.audioConfig.speechSpeed,
                range: 0.7...1.4,
                step: 0.05
            )

            // Pitch Shift
            sliderRow(
                title: state.t(.pitchControl),
                valueLabel: pitchLabel,
                tint: .purple,
                value: $state.audioConfig.pitchShiftSemitones,
                range: -6...6,
                step: 0.5
            )

            // Formant Clarity (F2 Emphasis)
            sliderRow(
                title: state.t(.clarityControl),
                valueLabel: "\(Int(state.audioConfig.formantClarity * 100))%",
                tint: .indigo,
                value: customBinding(\.formantClarity),
                range: 0.0...1.0,
                step: 0.05
            )

            // Loudness Boost (DSP Compression)
            sliderRow(
                title: state.t(.compressionControl),
                valueLabel: "\(Int(state.audioConfig.compressionAmount * 100))%",
                tint: .orange,
                value: customBinding(\.compressionAmount),
                range: 0.0...1.0,
                step: 0.05
            )

            // Motor Intensity
            sliderRow(
                title: state.t(.intensityControl),
                valueLabel: "\(Int(state.audioConfig.motorIntensity * 100))%",
                tint: .pink,
                value: customBinding(\.motorIntensity),
                range: 0.3...1.0,
                step: 0.05
            )

            Divider().opacity(0.35)

            // External Magic Trackpad toggle
            Toggle(isOn: $state.preferExternalTrackpad) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.t(.externalTrackpadToggle))
                        .font(.system(size: 11, weight: .medium))
                    Text(state.t(.externalTrackpadHint))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.purple)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var pitchLabel: String {
        let st = state.audioConfig.pitchShiftSemitones
        if abs(st) < 0.01 { return "0 st" }
        return String(format: "%+.1f st", st)
    }

    private func customBinding(_ keyPath: WritableKeyPath<HapticAudioConfig, Double>) -> Binding<Double> {
        Binding(
            get: { state.audioConfig[keyPath: keyPath] },
            set: { newValue in
                state.audioConfig[keyPath: keyPath] = newValue
                state.audioConfig.preset = .custom
            }
        )
    }

    private func sliderRow(
        title: String,
        valueLabel: String,
        tint: Color,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(tint)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .tint(tint)
        }
    }
}
