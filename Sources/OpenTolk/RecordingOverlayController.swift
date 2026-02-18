import AppKit
import SwiftUI

final class RecordingOverlayController {
    private var panel: NSPanel?
    private let stateModel = OverlayStateModel()

    func show(state: AppState) {
        stateModel.appState = state
        if panel == nil {
            createPanel()
        }
        panel?.orderFrontRegardless()
        positionAtBottomCenter()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let hostingController = NSHostingController(
            rootView: RecordingOverlayView(stateModel: stateModel)
        )
        // Let SwiftUI determine the size
        let fittingSize = hostingController.sizeThatFits(in: NSSize(width: 200, height: 200))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController

        self.panel = panel
    }

    private func positionAtBottomCenter() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.origin.y + 60
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class OverlayStateModel: ObservableObject {
    @Published var appState: AppState = .recording
}
