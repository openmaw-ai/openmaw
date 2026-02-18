import Foundation

final class LocalTranscriber: TranscriptionProvider {
    let providerType: TranscriptionProviderType = .local

    func transcribe(audio: RecordedAudio) async throws -> TranscriptionResult {
        throw TranscriptionError.notAvailable
    }
}
