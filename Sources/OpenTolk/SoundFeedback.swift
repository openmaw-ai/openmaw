import AppKit

enum SoundFeedback {
    static func playRecordingStart() {
        NSSound(named: "Tink")?.play()
    }

    static func playRecordingStop() {
        NSSound(named: "Pop")?.play()
    }

    static func playSuccess() {
        NSSound(named: "Hero")?.play()
    }

    static func playError() {
        NSSound(named: "Basso")?.play()
    }
}
