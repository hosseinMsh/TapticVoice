import SwiftUI

public struct WaveformVisualizer: View {
    @ObservedObject var hapticEngine: HapticEngine
    var isPreviewPlaying: Bool

    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    public init(hapticEngine: HapticEngine, isPreviewPlaying: Bool = false) {
        self.hapticEngine = hapticEngine
        self.isPreviewPlaying = isPreviewPlaying
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header stats
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .scaleEffect(isActive ? 1.2 : 1.0)
                        .animation(isActive ? Animation.easeInOut(duration: 0.6).repeatForever() : .default, value: isActive)

                    Text(isActive ? "در حال بازتولید رزونانس هپتیک" : "حالت آماده‌باش (۱۰۰ تا ۴۰۰۰ هرتز)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isActive ? .green : .secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    if hapticEngine.currentF1 > 0 {
                        Text("F₁: \(Int(hapticEngine.currentF1)) Hz")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    if hapticEngine.currentF2 > 0 {
                        Text("F₂: \(Int(hapticEngine.currentF2)) Hz")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                    if hapticEngine.currentF0 > 0 {
                        Text("F₀: \(Int(hapticEngine.currentF0)) Hz")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.pink)
                    }
                }
            }

            // Spectrum Bars Canvas
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                GeometryReader { geo in
                    let barCount = 36
                    let spacing: CGFloat = 3
                    let totalSpacing = spacing * CGFloat(barCount - 1)
                    let barWidth = max(2, (geo.size.width - totalSpacing - 16) / CGFloat(barCount))

                    HStack(alignment: .center, spacing: spacing) {
                        ForEach(0..<barCount, id: \.self) { index in
                            let height = barHeight(index: index, total: barCount, maxHeight: geo.size.height - 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.blue.opacity(0.8),
                                            Color.purple,
                                            Color.pink.opacity(0.9)
                                        ]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: barWidth, height: height)
                                .animation(.easeOut(duration: 0.08), value: height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 58)
        }
        .onReceive(timer) { _ in
            if isActive {
                phase += 0.25
            }
        }
    }

    private var isActive: Bool {
        hapticEngine.isPlaying || isPreviewPlaying
    }

    private func barHeight(index: Int, total: Int, maxHeight: CGFloat) -> CGFloat {
        guard isActive else { return 4 }

        let normalizedIdx = Double(index) / Double(total)
        // Simulate formant peaks around F1 (~25%) and F2 (~65%)
        let f1Weight = exp(-pow((normalizedIdx - 0.28) / 0.15, 2))
        let f2Weight = exp(-pow((normalizedIdx - 0.65) / 0.18, 2))
        let wave = sin(normalizedIdx * 12.0 + phase) * 0.3 + 0.7

        let levelFactor = max(0.2, hapticEngine.level > 0 ? hapticEngine.level : 0.6)
        let dynamicHeight = (f1Weight * 0.6 + f2Weight * 0.4) * wave * levelFactor * Double(maxHeight)

        return CGFloat(max(4.0, min(Double(maxHeight), dynamicHeight)))
    }
}
