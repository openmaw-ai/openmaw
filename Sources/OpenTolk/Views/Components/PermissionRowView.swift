import SwiftUI
import AVFoundation

enum PermissionType: String {
    case microphone = "Microphone"
    case accessibility = "Accessibility"
}

struct PermissionRowView: View {
    let type: PermissionType
    @State private var isGranted: Bool = false
    @State private var pollTimer: Timer?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue)
                    .font(.headline)
                Text(isGranted ? "Granted" : "Not granted")
                    .font(.caption)
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            Spacer()

            if !isGranted {
                Button(buttonLabel) {
                    requestPermission()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkPermission()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                checkPermission()
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private var icon: String {
        switch type {
        case .microphone: return "mic.fill"
        case .accessibility: return "hand.raised.fill"
        }
    }

    private func checkPermission() {
        switch type {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: isGranted = true
            default: isGranted = false
            }
        case .accessibility:
            isGranted = AXIsProcessTrusted()
        }
    }

    private var buttonLabel: String {
        switch type {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                return "Open Settings"
            }
            return "Grant Access"
        case .accessibility:
            return "Open Settings"
        }
    }

    private func requestPermission() {
        switch type {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
                // Already denied — must open Settings to re-enable
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        isGranted = granted
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
                    }
                }
            }
        case .accessibility:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
