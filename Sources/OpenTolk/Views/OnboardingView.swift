import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var testRecorder: AudioRecorder?
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<4) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: testStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentStep < 3 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 400)
        .background(.ultraThinMaterial)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Welcome to OpenTolk")
                .font(.title2)
                .fontWeight(.bold)
            Text("Fast, accurate voice-to-text for macOS.\nDictate anywhere with a single keypress.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Permissions")
                .font(.title3)
                .fontWeight(.bold)
            Text("OpenTolk needs these permissions to work:")
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(spacing: 8) {
                PermissionRowView(type: .microphone)
                PermissionRowView(type: .accessibility)
            }
            .padding()
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 360)
        }
    }

    private var testStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.purple)
            Text("Test Dictation")
                .font(.title3)
                .fontWeight(.bold)
            Text("Try a quick test to make sure everything works.\nPress the button and say something.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Button {
                if isTesting {
                    stopTest()
                } else {
                    runTest()
                }
            } label: {
                HStack {
                    Image(systemName: isTesting ? "stop.circle.fill" : "mic.circle.fill")
                    Text(isTesting ? "Stop Recording" : "Start Test Recording")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isTesting ? .red : .blue)

            if let result = testResult {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're all set!")
                .font(.title2)
                .fontWeight(.bold)
            Text("Press Right Option (\u{2325}) anytime to start dictating.\nQuick tap for auto-stop, hold for manual control.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Quick tap \u{2192} auto-stops on silence", systemImage: "hand.tap")
                Label("Hold \u{2192} records until you release", systemImage: "hand.raised")
                Label("Text is pasted where your cursor is", systemImage: "cursor.rays")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func runTest() {
        isTesting = true
        let recorder = AudioRecorder()
        testRecorder = recorder
        recorder.onSilenceStop = { audio in
            DispatchQueue.main.async {
                isTesting = false
                testRecorder = nil
                guard let audio = audio else {
                    testResult = "No audio captured. Check microphone permission."
                    return
                }
                let provider = TranscriberFactory.makeProvider()
                Task {
                    do {
                        let result = try await provider.transcribe(audio: audio)
                        await MainActor.run {
                            testResult = result.text.isEmpty ? "No speech detected." : "\"\(result.text)\""
                        }
                    } catch {
                        await MainActor.run {
                            testResult = "Error: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        recorder.recordUntilSilence()
    }

    private func stopTest() {
        guard let recorder = testRecorder else { return }
        let audio = recorder.stopRecording()
        isTesting = false
        testRecorder = nil
        guard let audio = audio else {
            testResult = "No audio captured."
            return
        }
        let provider = TranscriberFactory.makeProvider()
        Task {
            do {
                let result = try await provider.transcribe(audio: audio)
                await MainActor.run {
                    testResult = result.text.isEmpty ? "No speech detected." : "\"\(result.text)\""
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
