import SwiftUI

public struct ControlsView: View {
    @Binding var pitchHz: Double
    @Binding var speedPct: Double
    @Binding var intensity: Double
    @Binding var hapticMastering: Bool

    public init(
        pitchHz: Binding<Double>,
        speedPct: Binding<Double>,
        intensity: Binding<Double>,
        hapticMastering: Binding<Bool>
    ) {
        self._pitchHz = pitchHz
        self._speedPct = speedPct
        self._intensity = intensity
        self._hapticMastering = hapticMastering
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Pitch Control
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Button(action: { pitchHz = 0 }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .opacity(pitchHz != 0 ? 1 : 0)

                    Text(pitchText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.purple)

                    Spacer()

                    Text("زیر و بمی صدا (Pitch)")
                        .font(.system(size: 12, weight: .medium))
                }

                Slider(value: $pitchHz, in: -30...30, step: 2)
                    .tint(.purple)
            }

            // Speed Control
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Button(action: { speedPct = 0 }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .opacity(speedPct != 0 ? 1 : 0)

                    Text(speedText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)

                    Spacer()

                    Text("سرعت ادای گفتار (Speed)")
                        .font(.system(size: 12, weight: .medium))
                }

                Slider(value: $speedPct, in: -30...40, step: 5)
                    .tint(.blue)
            }

            // Actuation Intensity
            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Text("\(Int(intensity * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.pink)

                    Spacer()

                    Text("شدت لرزش شیشه ترک‌پد")
                        .font(.system(size: 12, weight: .medium))
                }

                Slider(value: $intensity, in: 0.5...1.0, step: 0.05)
                    .tint(.pink)
            }

            Divider()
                .opacity(0.4)

            // Mastering Toggle
            Toggle(isOn: $hapticMastering) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("مسترینگ آکوستیک بازه ۱۰۰ تا ۴۰۰۰ هرتز")
                        .font(.system(size: 12, weight: .medium))
                    Text("اکولایزر بهینه + تقویت تشدید فرکانس‌های ۱kHz و ۲.۲kHz")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(.purple)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var pitchText: String {
        let val = Int(pitchHz)
        if val == 0 { return "طبیعی (۰ Hz)" }
        return val > 0 ? "+\(val) Hz" : "\(val) Hz"
    }

    private var speedText: String {
        let val = Int(speedPct)
        if val == 0 { return "طبیعی (۰٪)" }
        return val > 0 ? "+\(val)٪" : "\(val)٪"
    }
}
