import SwiftUI
import TapticCore

/// Smooth 30 FPS canvas visualizer reading lock-free `TelemetrySnapshot` from `HapticEngine`.
public struct WaveformVisualizer: View {
    @EnvironmentObject private var state: AppState
    @State private var phase: Double = 0
    @State private var telemetry = TelemetrySnapshot()

    private let timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                        .scaleEffect(isActive ? 1.25 : 1.0)
                        .animation(.easeInOut(duration: 0.45), value: isActive)

                    Text(isActive ? state.t(.visualizerActive) : state.t(.visualizerIdle))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isActive ? .green : .secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    if telemetry.f1 > 0 {
                        telemetryPill("F₁", value: "\(Int(telemetry.f1)) Hz", color: .blue)
                    }
                    if telemetry.f2 > 0 {
                        telemetryPill("F₂", value: "\(Int(telemetry.f2)) Hz", color: .purple)
                    }
                    if telemetry.f0 > 0 {
                        telemetryPill("F₀", value: "\(Int(telemetry.f0)) Hz", color: .pink)
                    }
                }
            }

            Canvas { context, size in
                let barCount = 40
                let spacing: CGFloat = 3.0
                let horizontalPad: CGFloat = 10.0
                let usableWidth = max(10, size.width - horizontalPad * 2)
                let barWidth = max(2, (usableWidth - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
                let midY = size.height / 2.0

                for i in 0..<barCount {
                    let h = barHeight(index: i, total: barCount, maxHeight: size.height - 14)
                    let x = horizontalPad + CGFloat(i) * (barWidth + spacing)
                    let rect = CGRect(x: x, y: midY - h / 2.0, width: barWidth, height: h)
                    let path = RoundedRectangle(cornerRadius: barWidth / 2.0).path(in: rect)

                    let ratio = Double(i) / Double(barCount)
                    let barColor: Color = isActive
                        ? Color(hue: 0.58 + ratio * 0.25, saturation: 0.78, brightness: 0.95)
                        : Color.secondary.opacity(0.25)
                    context.fill(path, with: .color(barColor))
                }
            }
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .onReceive(timer) { _ in
            telemetry = state.hapticEngine.readTelemetry()
            if isActive {
                phase += 0.28
            }
        }
    }

    private var isActive: Bool {
        state.hapticEngine.isPlaying || state.isSpeakerPlaying
    }

    private func telemetryPill(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.85))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func barHeight(index: Int, total: Int, maxHeight: CGFloat) -> CGFloat {
        guard isActive else { return 4 }

        let norm = Double(index) / Double(total)
        let f1Norm = telemetry.f1 > 0 ? min(0.45, max(0.1, (telemetry.f1 - 150.0) / 2200.0)) : 0.26
        let f2Norm = telemetry.f2 > 0 ? min(0.88, max(0.45, (telemetry.f2 - 600.0) / 3000.0)) : 0.65

        let f1Peak = exp(-pow((norm - f1Norm) / 0.13, 2))
        let f2Peak = exp(-pow((norm - f2Norm) / 0.16, 2))
        let shimmer = sin(norm * 14.0 + phase) * 0.28 + 0.72

        let level = max(0.25, telemetry.level > 0 ? telemetry.level : 0.6)
        let rawH = (f1Peak * 0.58 + f2Peak * 0.42) * shimmer * level * Double(maxHeight)
        return CGFloat(max(4.0, min(Double(maxHeight), rawH)))
    }
}
