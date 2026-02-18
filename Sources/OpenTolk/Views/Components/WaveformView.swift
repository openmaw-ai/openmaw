import SwiftUI

struct WaveformView: View {
    @State private var phase: CGFloat = 0
    var isAnimating: Bool

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let barCount = 24
            let barWidth: CGFloat = 3
            let spacing = (size.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)

            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + spacing)
                let normalizedHeight: CGFloat
                if isAnimating {
                    let wave = sin(CGFloat(i) * 0.4 + phase) * 0.5 + 0.5
                    let secondary = sin(CGFloat(i) * 0.7 + phase * 1.3) * 0.3
                    normalizedHeight = max(0.1, wave + secondary)
                } else {
                    normalizedHeight = 0.1
                }

                let barHeight = normalizedHeight * size.height * 0.8
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(.red.opacity(0.8)))
            }
        }
        .onAppear {
            guard isAnimating else { return }
            startAnimation()
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue { startAnimation() }
        }
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }
}
