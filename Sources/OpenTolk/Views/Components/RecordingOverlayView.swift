import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var stateModel: OverlayStateModel

    @State private var dotIndex: Int = 0
    @State private var pulse = false
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            if stateModel.appState == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.4 : 1.0)
                    .opacity(pulse ? 0.6 : 1.0)
            } else {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .opacity(index == dotIndex ? 1.0 : 0.35)
                        .animation(.easeInOut(duration: 0.25), value: dotIndex)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.black)
        )
        .onReceive(timer) { _ in
            dotIndex = (dotIndex + 1) % 3
            if stateModel.appState == .recording {
                withAnimation(.easeInOut(duration: 0.6)) {
                    pulse.toggle()
                }
            } else {
                pulse = false
            }
        }
    }
}
