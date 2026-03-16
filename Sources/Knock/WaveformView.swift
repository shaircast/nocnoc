import SwiftUI

struct WaveformView: View {
    let values: [Double]
    let threshold: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x0D0F11), Color(hex: 0x060808)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Canvas { context, size in
                    let midY = size.height * 0.5
                    let thresholdY = max(size.height * (1 - threshold), 0)

                    var baseline = Path()
                    baseline.move(to: CGPoint(x: 0, y: midY))
                    baseline.addLine(to: CGPoint(x: size.width, y: midY))
                    context.stroke(baseline, with: .color(.white.opacity(0.08)), lineWidth: 1)

                    var thresholdPath = Path()
                    thresholdPath.move(to: CGPoint(x: 0, y: thresholdY))
                    thresholdPath.addLine(to: CGPoint(x: size.width, y: thresholdY))
                    context.stroke(thresholdPath, with: .color(Theme.warning.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                    guard values.count > 1 else { return }
                    let stepX = size.width / CGFloat(max(values.count - 1, 1))
                    var waveformPath = Path()
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = size.height - CGFloat(min(max(value, 0), 1.2) / 1.2) * size.height
                        if index == 0 {
                            waveformPath.move(to: CGPoint(x: x, y: y))
                        } else {
                            waveformPath.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    context.addFilter(.shadow(color: Theme.accent.opacity(0.55), radius: 6))
                    context.stroke(waveformPath, with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x39FF14), Color(hex: 0x7FFF6B), Color(hex: 0xCCFFCC)]),
                        startPoint: CGPoint(x: 0, y: size.height),
                        endPoint: CGPoint(x: size.width, y: 0)
                    ), lineWidth: 2)
                }
                .padding(12)
            }
        }
    }
}
